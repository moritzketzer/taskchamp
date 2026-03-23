# Phase 1.5: Bridge → TaskChamp Integration

## Summary

Replace TaskChamp's private `task-champion-swift` dependency with the public `taskchampion-bridge` UniFFI bindings. Minimal-invasive migration — only swap the FFI layer, don't restructure the app.

## Goal

Validate that `taskchampion-bridge` works as a drop-in replacement. TaskChamp fork builds, runs, and syncs using our public bridge.

## Architecture

```
┌─────────────────────────────────────────┐
│  TaskChamp App (existing SwiftUI)       │
│  taskchamp/ + taskchampWidget/          │
├─────────────────────────────────────────┤
│  taskchampShared (existing framework)   │
│  ┌────────────────────────────────────┐ │
│  │ BridgeAdapter.swift  ← NEW        │ │
│  │ Maps UniFFI types to app types     │ │
│  ├────────────────────────────────────┤ │
│  │ TaskchampionService.swift  ← EDIT  │ │
│  │ TCTask.swift               ← EDIT  │ │
│  │ SyncServiceProtocol.swift  ← EDIT  │ │
│  │ TCTag.swift                ← EDIT  │ │
│  └────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│  taskchampion-bridge (our UniFFI crate) │
│  via Swift Package (local path)         │
└─────────────────────────────────────────┘
```

## Part 1: Bridge Extension — Annotation Support

Before touching TaskChamp, extend `taskchampion-bridge` with annotation methods.

### New methods on `BridgeReplica`

| Method | Signature | Purpose |
|--------|-----------|---------|
| `addAnnotation` | `(uuid: String, description: String, timestamp: Int64) -> Result<(), BridgeError>` | Add annotation to existing task |
| `removeAnnotation` | `(uuid: String, timestamp: Int64) -> Result<(), BridgeError>` | Remove annotation by timestamp |

These use taskchampion's `Task::add_annotation()` and `Task::remove_annotation()` internally.

### Files changed in bridge repo

| Action | File |
|--------|------|
| Edit | `src/replica.rs` — add `add_annotation` and `remove_annotation` methods |
| Edit | `tests/integration.rs` — add annotation tests |

### Rebuild XCFramework

After adding annotation methods, rebuild the XCFramework + Swift bindings so TaskChamp can consume the updated API.

## Part 2: Dependency Swap

### Tuist/Package.swift

Replace:
```swift
Package.Dependency.package(
    name: "Taskchampion",
    path: "../task-champion-swift/taskchampion-swift/taskchampion-swift/"
)
```

With:
```swift
Package.Dependency.package(
    name: "TaskchampionBridge",
    path: "../bridge"
)
```

### Project.swift

In `taskchampShared` target, replace:
```swift
.external(name: "Taskchampion")
```

With:
```swift
.external(name: "TaskchampionBridge")
```

## Part 3: Adapter Layer

Create `taskchampShared/Sources/Services/BridgeAdapter.swift` — a thin mapping layer.

### Purpose

The old `task-champion-swift` uses swift-bridge types (`RustString`, `RustVec<T>`, `TaskRef`). Our UniFFI bridge uses native Swift types (`String`, `[String]`, `BridgeTaskData`). The adapter bridges this gap so the rest of the app needs minimal changes.

### Type mapping

| Old (swift-bridge) | New (UniFFI) | Notes |
|---------------------|-------------|-------|
| `Replica` | `BridgeReplica` | Arc-wrapped UniFFI Object |
| `TaskRef` | `BridgeTaskData` | Swift Record (struct), not a reference |
| `RustString` / `.intoRustString()` | `String` | Native, no conversion needed |
| `RustVec<Tag>` | `[String]` | Plain string array |
| `Annotation` (Rust obj) | `BridgeAnnotation` | Record with description + timestamp |
| `replica.all_tasks() -> [TaskRef]?` | `replica.allTasks() -> [BridgeTaskData]` | Throws instead of nil |
| `replica.sync_no_server()` | `replica.rebuildWorkingSet()` | Renamed |
| `replica.sync_remote_server(url, id, secret)` | `replica.syncRemote(url:clientId:encryptionSecret:)` | Named params, throws |
| `replica.sync_local_server(path)` | `replica.syncLocal(serverDir:)` | Named params, throws |
| `replica.sync_gcp(bucket, cred, secret)` | `replica.syncGcp(bucket:credentialPath:encryptionSecret:)` | Named params, throws |
| `replica.sync_aws(region, bucket, key, secret, enc)` | `replica.syncAws(bucket:encryptionSecret:region:...)` | Different param order, throws |

### Behavior changes the adapter must handle

1. **Error model:** Old returns `nil`/`Bool` on failure → New throws `BridgeError`. The adapter wraps calls in do/catch where needed, or we update call sites to use try/catch (preferred — it's cleaner).

2. **Task creation:** Old takes UUID as parameter → New generates UUID internally. `TaskchampionService.createTask` currently passes `task.uuid` — adapter ignores this since the bridge generates it, and returns the bridge-generated UUID.

3. **Task data access:** Old uses reference types with getters (`rustTask.get_description().toString()`) → New uses value types with properties (`bridgeTask.description`). This simplifies `TCTask.init`.

4. **Sync return values:** Old returns `Bool` → New throws on failure, succeeds silently. Adapter translates: success = true, catch = false.

## Part 4: File-by-File Changes

### `taskchampShared/Sources/Services/TaskchampionService.swift`

- Replace `import Taskchampion` → `import TaskchampionBridge`
- Change `private var replica: Replica?` → `private var replica: BridgeReplica?`
- `setDbUrl`: Replace `Taskchampion.new_replica_on_disk(path, true, true)` → `try BridgeReplica.open(path: path, createIfMissing: true)`
- `createTask`: Remove `task.uuid` parameter, adapt to new `createTask(description:status:priority:due:project:tags:)` signature. Handle returned `BridgeTaskData` (contains generated UUID).
- `updateTask`: Adapt to new `updateTask(uuid:description:status:priority:due:project:tags:)` signature. Remove `intoRustString()` calls. Handle annotations separately via `addAnnotation`/`removeAnnotation`.
- `getTasks`/`getPendingTasks`/`getTask`: Replace `replica.all_tasks()` → `try replica.allTasks()`, etc. Remove nil-checks, use try/catch.
- `sync_no_server()` calls → `rebuildWorkingSet()`

### `taskchampShared/Sources/Models/TCTask.swift`

- Replace `import Taskchampion` → `import TaskchampionBridge`
- Replace `init(from rustTask: TaskRef)` → `init(from bridgeTask: BridgeTaskData)`
  - `rustTask.get_uuid().to_string().toString()` → `bridgeTask.uuid`
  - `rustTask.get_description().toString()` → `bridgeTask.description`
  - `rustTask.get_status().get_value().toString().lowercased()` → map from `bridgeTask.status` enum
  - `rustTask.get_priority().toString()` → map from `bridgeTask.priority` enum
  - `rustTask.get_due()?.toString()` → `bridgeTask.due` (already Int64 timestamp)
  - `rustTask.get_project()?.toString()` → `bridgeTask.project`
  - `rustTask.get_tags().map { ... }` → `bridgeTask.tags.map { TCTag.tagFactory(name: $0) }`
  - `rustTask.get_annotations().map { ... }` → `bridgeTask.annotations.map { $0.description }`
- Replace `taskFactory(from rustTask: TaskRef, ...)` → `taskFactory(from bridgeTask: BridgeTaskData, ...)`
  - Same property access pattern as above
- Remove `rustVecOfTags` computed property (no longer needed — tags are `[String]`)
- Remove `rustAnnotationFromObsidianNote` (replace with direct `addAnnotation` call in service layer)

### `taskchampShared/Sources/Services/SyncServiceProtocol.swift`

- Replace `import Taskchampion` → `import TaskchampionBridge`
- Change protocol: `static func sync(replica: Replica)` → `static func sync(replica: BridgeReplica)`
- `NoSyncService.sync`: `replica.sync_no_server()` → `try replica.rebuildWorkingSet(); return true`
- `ICloudSyncService.sync`: `replica.sync_local_server(path)` → `try replica.syncLocal(serverDir: path); return true`
- `RemoteSyncService.sync`: Replace `intoRustString()` calls, use `try replica.syncRemote(url:clientId:encryptionSecret:); return true`
- `GcpSyncService.sync`: Same pattern with `syncGcp`
- `AwsSyncService.sync`: Same pattern with `syncAws`
- All sync methods: wrap in do/catch, return `false` on error (or rethrow)

### `taskchampShared/Sources/Models/TCTag.swift`

- Remove `import Taskchampion` if present
- Tags are now plain `String` — no `Tag` Rust type to convert from
- `TCTag.tagFactory` likely needs no changes (already takes `name: String`)

## Out of Scope

- App architecture changes or refactoring
- New features
- Android/Kotlin bindings
- Phase 2 Modern API Layer
- Publishing bridge to Swift Package Registry
- CI/CD changes

## Validation Criteria

Phase 1.5 is complete when:

1. `tuist generate` produces an Xcode project without errors
2. Project builds in Xcode (Debug + Release) for iOS
3. App launches in Simulator and displays task list
4. Task create, edit, delete works correctly
5. Sync with taskchampion-sync-server works (if server available)
6. Obsidian note annotation survives task update round-trip
