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
| `addAnnotation` | `(uuid: String, description: String, timestamp: Int64) throws -> ()` | Add annotation to existing task |
| `removeAnnotation` | `(uuid: String, timestamp: Int64) throws -> ()` | Remove annotation by timestamp |

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

### Type mapping (complete)

| Old (swift-bridge) | New (UniFFI) | Notes |
|---------------------|-------------|-------|
| `Replica` | `BridgeReplica` | Arc-wrapped UniFFI Object |
| `TaskRef` | `BridgeTaskData` | Swift Record (struct), not a reference |
| `RustString` / `.intoRustString()` | `String` | Native, no conversion needed |
| `RustVec<Tag>` | `[String]` | Plain string array |
| `Annotation` (Rust obj) | `BridgeAnnotation` | Record with description + timestamp |
| `Tag` (Rust obj) | `String` | Plain string, no Rust type |
| `replica.all_tasks() -> [TaskRef]?` | `try replica.allTasks() -> [BridgeTaskData]` | Throws instead of nil |
| `replica.pending_tasks() -> [TaskRef]?` | `try replica.pendingTasks() -> [BridgeTaskData]` | Throws instead of nil |
| `replica.get_task(uuid) -> TaskRef?` | `try replica.getTask(uuid:) -> BridgeTaskData` | Throws TaskNotFound instead of nil |
| `replica.sync_no_server() -> Bool` | `try replica.rebuildWorkingSet()` | Renamed, throws |
| `replica.sync_remote_server(url, id, secret) -> Bool` | `try replica.syncRemote(url:clientId:encryptionSecret:)` | Named params, throws |
| `replica.sync_local_server(path) -> Bool` | `try replica.syncLocal(serverDir:)` | Named params, throws |
| `replica.sync_gcp(bucket, cred, secret) -> Bool` | `try replica.syncGcp(bucket:credentialPath:encryptionSecret:)` | Named params, throws |
| `replica.sync_aws(region, bucket, key, secret, enc) -> Bool` | `try replica.syncAws(bucket:encryptionSecret:region:endpointUrl:forcePathStyle:accessKeyId:secretAccessKey:)` | 7 params, see below |

### AWS sync — full signature

Old call (5 params):
```swift
replica.sync_aws(region, bucket, accessKeyId, secretAccessKey, encryptionSecret)
```

New call (7 params):
```swift
try replica.syncAws(
    bucket: bucket,
    encryptionSecret: encryptionSecret,
    region: region,            // String?
    endpointUrl: nil,          // String? — new, not used by TaskChamp
    forcePathStyle: false,     // Bool — new, not used by TaskChamp
    accessKeyId: accessKeyId,  // String?
    secretAccessKey: secretAccessKey  // String?
)
```

### Enum mapping (bidirectional)

The adapter must provide conversion functions in both directions.

**Bridge → App (reading tasks):**

| `TaskStatus` | `TCTask.Status` |
|---|---|
| `.pending` | `.pending` |
| `.completed` | `.completed` |
| `.deleted` | `.deleted` |

| `TaskPriority?` | `TCTask.Priority` |
|---|---|
| `.high` | `.high` (rawValue "H") |
| `.medium` | `.medium` (rawValue "M") |
| `.low` | `.low` (rawValue "L") |
| `nil` | `.none` (rawValue "None") |

**App → Bridge (creating/updating tasks):**

| `TCTask.Status` | `TaskStatus` |
|---|---|
| `.pending` | `.pending` |
| `.completed` | `.completed` |
| `.deleted` | `.deleted` |

| `TCTask.Priority` | `TaskPriority?` |
|---|---|
| `.high` | `.high` |
| `.medium` | `.medium` |
| `.low` | `.low` |
| `.none` / `nil` | `nil` |

### Due date conversion

Old code converts due to string timestamp:
```swift
let due = task.due?.timeIntervalSince1970.rounded()
let dueString = due != nil ? String(Int(due ?? 0)) : nil
// then: dueString?.intoRustString()
```

New bridge takes `Int64?` directly:
```swift
let dueTimestamp: Int64? = task.due.map { Int64($0.timeIntervalSince1970.rounded()) }
// then: dueTimestamp passed directly to createTask/updateTask
```

### Annotation update strategy

The old `updateTask` does a full annotation replacement — creates a `RustVec<Annotation>` and passes it inline. Our bridge's `updateTask` doesn't accept annotations, only `addAnnotation`/`removeAnnotation` on individual tasks.

**Strategy for Obsidian note annotation in `TaskchampionService.updateTask`:**

1. After calling `updateTask(...)` for the core properties, handle annotations separately
2. If the task has an `obsidianNoteAnnotation`:
   - Get the current task's annotations via `getTask(uuid:)` to see existing state
   - Find any existing annotation whose description starts with `"task-note: "` — this is the Obsidian annotation
   - If found and different from new value: call `removeAnnotation(uuid:timestamp:)` then `addAnnotation(uuid:description:timestamp:)`
   - If not found: call `addAnnotation(uuid:description:timestamp:)` with the new note
   - If task no longer has an obsidianNoteAnnotation but one exists: call `removeAnnotation(uuid:timestamp:)`

This preserves the existing behavior while using the add/remove API.

### Behavior changes the adapter must handle

1. **Error model:** Old returns `nil`/`Bool` on failure → New throws `BridgeError`. Update call sites from nil-checks to try/catch.

2. **Task creation:** Old takes UUID as parameter → New generates UUID internally. `TaskchampionService.createTask` currently passes `task.uuid` — the bridge ignores this and generates its own. The returned `BridgeTaskData` contains the bridge-generated UUID.

3. **Task data access:** Old uses reference types with getters (`rustTask.get_description().toString()`) → New uses value types with properties (`bridgeTask.description`). This simplifies `TCTask.init`.

4. **Sync return values:** Old returns `Bool` → New throws on failure, succeeds silently. Wrap in do/catch: success = true, catch = false (or rethrow).

## Part 4: File-by-File Changes

### `taskchampShared/Sources/Services/TaskchampionService.swift`

- Replace `import Taskchampion` → `import TaskchampionBridge`
- Change `private var replica: Replica?` → `private var replica: BridgeReplica?`
- `setDbUrl`: Replace `Taskchampion.new_replica_on_disk(path, true, true)` → `try BridgeReplica.open(path: path, createIfMissing: true)`. Change from nil-check to try/catch.
- `createTask`:
  - Remove UUID parameter (bridge generates it)
  - Map `TCTask.Status` → `TaskStatus` enum
  - Map `TCTask.Priority` → `TaskPriority?` enum
  - Convert due date: `Date?` → `Int64?` (unix timestamp)
  - Pass tags as `[String]` (map from `task.tags?.map { $0.name } ?? []`)
  - No `intoRustString()` calls — all native types
  - Handle returned `BridgeTaskData` for UUID
- `updateTask`:
  - Same enum/type conversions as createTask
  - Replace `dueString` (String) with `dueTimestamp` (Int64?)
  - Remove `intoRustString()` calls
  - Remove inline annotation passing — handle annotations separately after update (see annotation strategy above)
  - Remove `rustVecOfTags` usage — pass `[String]` directly
- `getTasks`/`getPendingTasks`/`getTask`: Replace optional returns with try/catch:
  - `replica.all_tasks()` → `try replica.allTasks()`
  - `replica.pending_tasks()` → `try replica.pendingTasks()`
  - `replica.get_task(uuid)` → `try replica.getTask(uuid: uuid)`
  - Remove `guard let tasks else` nil-checks — these now throw on failure
- `sync_no_server()` calls → `try rebuildWorkingSet()`

### `taskchampShared/Sources/Models/TCTask.swift`

- Replace `import Taskchampion` → `import TaskchampionBridge`
- Replace `init(from rustTask: TaskRef)` → `init(from bridgeTask: BridgeTaskData)`:
  - `rustTask.get_uuid().to_string().toString()` → `bridgeTask.uuid`
  - `rustTask.get_description().toString()` → `bridgeTask.description`
  - `rustTask.get_status().get_value().toString().lowercased()` → map `bridgeTask.status` via enum conversion
  - `rustTask.get_priority().toString()` → map `bridgeTask.priority` via enum conversion
  - `rustTask.get_due()?.toString()` → `bridgeTask.due` (Int64? → Date? via `Date(timeIntervalSince1970: TimeInterval(ts))`)
  - `rustTask.get_project()?.toString()` → `bridgeTask.project`
  - `rustTask.get_tags().map { ... }` → `bridgeTask.tags.map { TCTag.tagFactory(name: $0) }`
  - `rustTask.get_annotations().map { ... }` → `bridgeTask.annotations.map { $0.description }`
- Replace `taskFactory(from rustTask: TaskRef, ...)` → `taskFactory(from bridgeTask: BridgeTaskData, ...)`:
  - `rustTask.get_priority().toString()` → map from `bridgeTask.priority` enum to rawValue string
  - `rustTask.get_project()?.toString()` → `bridgeTask.project ?? ""`
  - `rustTask.get_status().get_value().toString().lowercased()` → map from `bridgeTask.status` enum
  - Tag filtering: `rustTask.get_tags().map { $0.get_value().toString }` → `bridgeTask.tags` (already `[String]`)
- **Remove** `rustVecOfTags` computed property (no longer needed — tags are `[String]`)
- **Remove** `rustAnnotationFromObsidianNote` computed property (annotation handling moves to service layer)
- **Remove** `rustTags` computed property (no longer needed)

### `taskchampShared/Sources/Services/SyncServiceProtocol.swift`

- Replace `import Taskchampion` → `import TaskchampionBridge`
- Change protocol: `static func sync(replica: Replica)` → `static func sync(replica: BridgeReplica)`
- `NoSyncService.sync`: `replica.sync_no_server()` → `try replica.rebuildWorkingSet(); return true`
- `ICloudSyncService.sync`: `replica.sync_local_server(icloudPath)` → `try replica.syncLocal(serverDir: icloudPath); return true`. Remove `DispatchQueue.main.async` wrapper (bridge calls are synchronous, already blocking).
- `RemoteSyncService.sync`: Remove `intoRustString()` calls:
  ```swift
  try replica.syncRemote(
      url: remoteServerUrl,
      clientId: remoteClientId,
      encryptionSecret: remoteEncryptionSecret
  )
  return true
  ```
- `GcpSyncService.sync`:
  ```swift
  try replica.syncGcp(
      bucket: bucket,
      credentialPath: getGcpCredentialPath(),
      encryptionSecret: encryptionSecret
  )
  return true
  ```
- `AwsSyncService.sync`:
  ```swift
  try replica.syncAws(
      bucket: bucket,
      encryptionSecret: encryptionSecret,
      region: region,
      endpointUrl: nil,
      forcePathStyle: false,
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey
  )
  return true
  ```
- All sync methods: remove `DispatchQueue.main.async` + `withCheckedContinuation` wrapping since bridge calls are synchronous (block_on internally). Keep `async` in signature for protocol compatibility but call synchronously.

### `taskchampShared/Sources/Models/TCTag.swift`

- Remove `import Taskchampion`
- **Remove** `rustTag` computed property (was: `Taskchampion.create_tag(name)`)
- **Replace** `isSynthetic()` with pure-Swift implementation:
  ```swift
  public func isSynthetic() -> Bool {
      return name.hasPrefix("_")
  }
  ```
  Rationale: In taskchampion, synthetic tags start with `_` (e.g. `_PENDING`, `_ACTIVE`). Our bridge already filters synthetic tags on read (`tag.is_user()` in Rust), so this is mainly a guard for manually-entered tags.
- **Replace** `isValid()` with pure-Swift validation:
  ```swift
  public func isValid() -> Bool {
      guard !name.isEmpty else { return false }
      let pattern = /^[a-zA-Z0-9._]+$/
      return name.wholeMatch(of: pattern) != nil && !isSynthetic()
  }
  ```
  Rationale: taskchampion's `Tag::from_str()` validates that tags match `[a-zA-Z0-9._]+` and aren't synthetic. We replicate this in Swift.

### Files that use TCTag methods (verify only — no changes expected)

These files call `tag.isSynthetic()` and `tag.isValid()`. Since the method signatures don't change, they should work without modification after the TCTag changes above:

- `taskchamp/Sources/View/AddTagView.swift` — calls `tag.isSynthetic()` (lines 51, 167, 169), `tag.isValid()` (line 57)
- `taskchampShared/Sources/Services/NLPService.swift` — calls `tag.isValid()` (line 91), `tag.isSynthetic()` (line 94), `tag.isValid()` (line 120)

These should be verified during testing but require no code changes.

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
