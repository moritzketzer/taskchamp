# Phase 1.5: Bridge → TaskChamp Integration — Implementation Plan

> **For agentic workers:** REQUIRED: Use subagent-driven-development (if subagents available) or executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace TaskChamp's private `task-champion-swift` with the public `taskchampion-bridge`, proving it works as a drop-in replacement.

**Architecture:** Two-repo change. First extend the bridge crate with annotation support and rebuild the XCFramework. Then swap the dependency in TaskChamp and adapt the Swift code file-by-file, using an adapter layer for enum/type mapping.

**Tech Stack:** Rust (bridge), Swift/SwiftUI (TaskChamp), Tuist (build system), UniFFI (FFI layer)

---

## File Structure

### Bridge repo (`~/para/0-System/taskwarrior-mobile/bridge`)

| Action | File | Responsibility |
|--------|------|----------------|
| Edit | `src/replica.rs` | Add `add_annotation` and `remove_annotation` methods |
| Edit | `tests/integration.rs` | Add annotation round-trip tests |

### TaskChamp repo (`~/para/0-System/taskwarrior-mobile/taskchamp`)

| Action | File | Responsibility |
|--------|------|----------------|
| Edit | `Tuist/Package.swift` | Swap dependency declaration |
| Edit | `Project.swift` | Update external dependency name |
| Create | `taskchampShared/Sources/Services/BridgeAdapter.swift` | Enum/type mapping between bridge and app types |
| Edit | `taskchampShared/Sources/Models/TCTag.swift` | Remove Taskchampion import, pure-Swift tag validation |
| Edit | `taskchampShared/Sources/Models/TCTask.swift` | Adapt to BridgeTaskData, remove Rust type helpers |
| Edit | `taskchampShared/Sources/Services/TaskchampionService.swift` | Use BridgeReplica, new signatures, annotation handling |
| Edit | `taskchampShared/Sources/Services/SyncServiceProtocol.swift` | Use BridgeReplica, new sync signatures |

---

## Chunk 1: Bridge Annotation Support

### Task 1: Add annotation methods to bridge

**Files:**
- Edit: `~/para/0-System/taskwarrior-mobile/bridge/src/replica.rs`
- Edit: `~/para/0-System/taskwarrior-mobile/bridge/tests/integration.rs`

Work from: `~/para/0-System/taskwarrior-mobile/bridge` (branch: `main`)

- [ ] **Step 1: Add `add_annotation` method to BridgeReplica**

In `src/replica.rs`, add inside the existing `#[uniffi::export] impl BridgeReplica` block:

```rust
/// Add an annotation to an existing task.
pub fn add_annotation(
    &self,
    uuid: String,
    description: String,
    timestamp: i64,
) -> Result<(), BridgeError> {
    let parsed = Uuid::parse_str(&uuid).map_err(|e| BridgeError::InvalidData {
        message: format!("Invalid UUID '{uuid}': {e}"),
    })?;
    let mut replica = self.lock_replica()?;
    self.runtime.block_on(async {
        let mut task = replica
            .get_task(parsed)
            .await
            .map_err(tc_err)?
            .ok_or_else(|| BridgeError::TaskNotFound {
                uuid: uuid.clone(),
            })?;

        let mut ops = Operations::new();
        let entry = taskchampion::utc_timestamp(timestamp);
        task.add_annotation(entry, &description, &mut ops)
            .map_err(tc_err)?;
        replica.commit_operations(ops).await.map_err(tc_err)?;
        Ok(())
    })
}
```

Note: Check taskchampion docs for exact `add_annotation` signature. It may be `task.add_annotation(entry: DateTime, description: &str, ops: &mut Operations)` or similar. Consult `docs.rs/taskchampion/3.0.1/taskchampion/struct.Task.html` for the precise method.

- [ ] **Step 2: Add `remove_annotation` method to BridgeReplica**

```rust
/// Remove an annotation from an existing task by its timestamp.
pub fn remove_annotation(
    &self,
    uuid: String,
    timestamp: i64,
) -> Result<(), BridgeError> {
    let parsed = Uuid::parse_str(&uuid).map_err(|e| BridgeError::InvalidData {
        message: format!("Invalid UUID '{uuid}': {e}"),
    })?;
    let mut replica = self.lock_replica()?;
    self.runtime.block_on(async {
        let mut task = replica
            .get_task(parsed)
            .await
            .map_err(tc_err)?
            .ok_or_else(|| BridgeError::TaskNotFound {
                uuid: uuid.clone(),
            })?;

        let mut ops = Operations::new();
        let entry = taskchampion::utc_timestamp(timestamp);
        task.remove_annotation(entry, &mut ops)
            .map_err(tc_err)?;
        replica.commit_operations(ops).await.map_err(tc_err)?;
        Ok(())
    })
}
```

- [ ] **Step 3: Verify bridge compiles**

```bash
cd ~/para/0-System/taskwarrior-mobile/bridge
cargo check 2>&1 | tail -5
```

Expected: `Finished` with no errors.

- [ ] **Step 4: Add annotation integration tests**

In `tests/integration.rs`, add:

```rust
#[test]
fn test_add_and_read_annotation() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_str().unwrap().to_string();
    let replica = BridgeReplica::open(path, true).unwrap();

    let created = replica
        .create_task(
            "Annotated task".to_string(),
            TaskStatus::Pending,
            None,
            None,
            None,
            vec![],
        )
        .unwrap();

    let timestamp = 1700000000i64; // fixed timestamp for testing
    replica
        .add_annotation(created.uuid.clone(), "Test note".to_string(), timestamp)
        .unwrap();

    let fetched = replica.get_task(created.uuid.clone()).unwrap();
    assert_eq!(fetched.annotations.len(), 1);
    assert_eq!(fetched.annotations[0].description, "Test note");
    assert_eq!(fetched.annotations[0].timestamp, timestamp);
}

#[test]
fn test_remove_annotation() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_str().unwrap().to_string();
    let replica = BridgeReplica::open(path, true).unwrap();

    let created = replica
        .create_task(
            "Task with annotation".to_string(),
            TaskStatus::Pending,
            None,
            None,
            None,
            vec![],
        )
        .unwrap();

    let timestamp = 1700000000i64;
    replica
        .add_annotation(created.uuid.clone(), "To remove".to_string(), timestamp)
        .unwrap();

    // Verify annotation exists
    let fetched = replica.get_task(created.uuid.clone()).unwrap();
    assert_eq!(fetched.annotations.len(), 1);

    // Remove it
    replica
        .remove_annotation(created.uuid.clone(), timestamp)
        .unwrap();

    // Verify it's gone
    let fetched = replica.get_task(created.uuid.clone()).unwrap();
    assert_eq!(fetched.annotations.len(), 0);
}
```

- [ ] **Step 5: Run tests**

```bash
cargo test 2>&1 | tail -20
```

Expected: All tests pass (11 total — 9 existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add src/replica.rs tests/integration.rs
git commit -m "feat: ✨ add annotation support (add/remove)"
```

### Task 2: Rebuild XCFramework

**Files:**
- Output: `~/para/0-System/taskwarrior-mobile/bridge/output/`

Work from: `~/para/0-System/taskwarrior-mobile/bridge`

- [ ] **Step 1: Rebuild iOS targets and XCFramework**

The build requires fenix's Rust toolchain but the system clang for iOS cross-compilation. Use the following pattern:

```bash
FENIX="/nix/store/lzwxqjmw0ggsg6j0v0angx6hzya2cdn9-rust-mixed"
IOS_SDK="$(xcrun --show-sdk-path --sdk iphoneos)"
SIM_SDK="$(xcrun --show-sdk-path --sdk iphonesimulator)"

export PATH="$FENIX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export CC_aarch64_apple_ios="/usr/bin/clang"
export AR_aarch64_apple_ios="/usr/bin/ar"
export CC_aarch64_apple_ios_sim="/usr/bin/clang"
export AR_aarch64_apple_ios_sim="/usr/bin/ar"
export IPHONEOS_DEPLOYMENT_TARGET=15.0

# Build iOS device
SDKROOT="$IOS_SDK" cargo build --release --target aarch64-apple-ios

# Build iOS simulator
SDKROOT="$SIM_SDK" cargo build --release --target aarch64-apple-ios-sim

# Generate Swift bindings
cargo run --bin uniffi-bindgen -- generate \
    --library target/aarch64-apple-ios/release/libtaskchampion_bridge.a \
    --language swift \
    --out-dir output/swift

# Create XCFramework
mkdir -p output/headers
cp output/swift/taskchampion_bridgeFFI.h output/headers/
cat > output/headers/module.modulemap << 'EOF'
framework module TaskchampionBridgeFFI {
    header "taskchampion_bridgeFFI.h"
    export *
}
EOF

rm -rf output/TaskchampionBridge.xcframework
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libtaskchampion_bridge.a \
    -headers output/headers/ \
    -library target/aarch64-apple-ios-sim/release/libtaskchampion_bridge.a \
    -headers output/headers/ \
    -output output/TaskchampionBridge.xcframework
```

Note: The fenix path may differ. Find it with `nix develop --command bash -c 'which rustc'` and use the parent directory. If the store path has changed since last build, update accordingly.

Expected: `xcframework successfully written out to: .../output/TaskchampionBridge.xcframework`

- [ ] **Step 2: Verify XCFramework contents**

```bash
ls output/TaskchampionBridge.xcframework/
ls output/swift/
```

Expected: `ios-arm64/` + `ios-arm64-simulator/` in xcframework, `taskchampion_bridge.swift` + header files in swift/.

- [ ] **Step 3: Commit bridge changes and push**

```bash
git push origin main
```

---

## Chunk 2: Dependency Swap + Adapter Layer

### Task 3: Swap dependency in Tuist config

**Files:**
- Edit: `~/para/0-System/taskwarrior-mobile/taskchamp/Tuist/Package.swift`
- Edit: `~/para/0-System/taskwarrior-mobile/taskchamp/Project.swift`

Work from: `~/para/0-System/taskwarrior-mobile/taskchamp` (create branch: `feat/bridge-integration`)

- [ ] **Step 1: Create feature branch**

```bash
cd ~/para/0-System/taskwarrior-mobile/taskchamp
git checkout -b feat/bridge-integration
```

- [ ] **Step 2: Update Tuist/Package.swift**

Replace the `Taskchampion` dependency:

```swift
// OLD:
Package.Dependency.package(
    name: "Taskchampion",
    path: "../task-champion-swift/taskchampion-swift/taskchampion-swift/"
)

// NEW:
Package.Dependency.package(
    name: "TaskchampionBridge",
    path: "../bridge"
)
```

- [ ] **Step 3: Update Project.swift**

In the `taskchampShared` target's dependencies, replace:

```swift
// OLD:
.external(name: "Taskchampion")

// NEW:
.external(name: "TaskchampionBridge")
```

- [ ] **Step 4: Commit**

```bash
git add Tuist/Package.swift Project.swift
git commit -m "build: 🔧 swap task-champion-swift for taskchampion-bridge"
```

### Task 4: Create BridgeAdapter

**Files:**
- Create: `~/para/0-System/taskwarrior-mobile/taskchamp/taskchampShared/Sources/Services/BridgeAdapter.swift`

- [ ] **Step 1: Create the adapter file**

```swift
import Foundation
import TaskchampionBridge

// MARK: - Status Mapping

extension TaskStatus {
    /// Convert bridge TaskStatus to app's TCTask.Status
    var toAppStatus: TCTask.Status {
        switch self {
        case .pending: return .pending
        case .completed: return .completed
        case .deleted: return .deleted
        }
    }
}

extension TCTask.Status {
    /// Convert app's TCTask.Status to bridge TaskStatus
    var toBridgeStatus: TaskStatus {
        switch self {
        case .pending: return .pending
        case .completed: return .completed
        case .deleted: return .deleted
        }
    }
}

// MARK: - Priority Mapping

extension TaskPriority {
    /// Convert bridge TaskPriority to app's TCTask.Priority
    var toAppPriority: TCTask.Priority {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

extension TCTask.Priority {
    /// Convert app's TCTask.Priority to bridge TaskPriority (nil = no priority)
    var toBridgePriority: TaskPriority? {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        case .none: return nil
        }
    }
}

// MARK: - Due Date Conversion

extension Date {
    /// Convert Date to Int64 unix timestamp for the bridge
    var toBridgeTimestamp: Int64 {
        Int64(timeIntervalSince1970.rounded())
    }
}

extension Int64 {
    /// Convert bridge Int64 timestamp to Date
    var toDate: Date {
        Date(timeIntervalSince1970: TimeInterval(self))
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add taskchampShared/Sources/Services/BridgeAdapter.swift
git commit -m "feat: ✨ add BridgeAdapter for type mapping"
```

### Task 5: Update TCTag (pure-Swift tag validation)

**Files:**
- Edit: `~/para/0-System/taskwarrior-mobile/taskchamp/taskchampShared/Sources/Models/TCTag.swift`

- [ ] **Step 1: Replace Taskchampion dependency with pure-Swift**

Remove `import Taskchampion`. Remove the `rustTag` computed property. Replace `isSynthetic()` and `isValid()`:

```swift
// REMOVE this:
import Taskchampion

// REMOVE this computed property:
public var rustTag: Tag? {
    return Taskchampion.create_tag(name)
}

// REPLACE isSynthetic():
public func isSynthetic() -> Bool {
    return name.hasPrefix("_")
}

// REPLACE isValid():
public func isValid() -> Bool {
    guard !name.isEmpty else { return false }
    let pattern = /^[a-zA-Z0-9._]+$/
    return name.wholeMatch(of: pattern) != nil && !isSynthetic()
}
```

The file should have no remaining `Taskchampion` imports or Rust types after this change.

- [ ] **Step 2: Commit**

```bash
git add taskchampShared/Sources/Models/TCTag.swift
git commit -m "refactor: ♻️ replace Rust tag validation with pure-Swift"
```

---

## Chunk 3: Core Swift File Migration

### Task 6: Update TCTask model

**Files:**
- Edit: `~/para/0-System/taskwarrior-mobile/taskchamp/taskchampShared/Sources/Models/TCTask.swift`

- [ ] **Step 1: Replace import and init(from:)**

Replace `import Taskchampion` with `import TaskchampionBridge`.

Replace `init(from rustTask: TaskRef)` with:

```swift
public init(from bridgeTask: BridgeTaskData) {
    let uuid = bridgeTask.uuid
    let description = bridgeTask.description
    let status = bridgeTask.status.toAppStatus
    let priority = bridgeTask.priority?.toAppPriority ?? .none
    let due: Date? = bridgeTask.due.map { $0.toDate }
    let project = bridgeTask.project
    let annotations = bridgeTask.annotations.map { $0.description }
    let tags = bridgeTask.tags.map { TCTag.tagFactory(name: $0) }

    // Parse obsidian note annotation key from annotations
    var noteAnnotationKey: String? = nil
    for annotation in bridgeTask.annotations {
        if annotation.description.hasPrefix("task-note: ") {
            noteAnnotationKey = String(bridgeTask.annotations.firstIndex(where: { $0.timestamp == annotation.timestamp }) ?? 0)
        }
    }

    self.init(
        uuid: uuid,
        description: description,
        status: status,
        priority: priority,
        due: due,
        tags: tags,
        project: project,
        noteAnnotationKey: noteAnnotationKey
    )
}
```

Note: The exact `noteAnnotationKey` parsing logic should match the existing Codable init behavior. Check how the existing init derives `noteAnnotationKey` from the old `rustTask` and replicate that logic. The key is the annotation's dictionary key used in the TaskData format — inspect the existing code carefully.

- [ ] **Step 2: Replace taskFactory(from:withFilter:)**

Replace `taskFactory(from rustTask: TaskRef, withFilter filter: TCFilter)` — change parameter type and property access:

```swift
@MainActor
public static func taskFactory(from bridgeTask: BridgeTaskData, withFilter filter: TCFilter) -> TCTask? {
    let prio = bridgeTask.priority?.toAppPriority.rawValue ?? "None"
    if filter.didSetPrio {
        if prio != filter.priority.rawValue {
            return nil
        }
    }

    let project = bridgeTask.project ?? ""
    if filter.didSetProject {
        if project != filter.project {
            return nil
        }
    }

    let statusValue = bridgeTask.status.toAppStatus.rawValue
    if filter.didSetStatus {
        if statusValue != filter.status.rawValue {
            return nil
        }
    }

    if filter.didSetTags {
        let tagsToInclude = filter.tagsToInclude
        let tagsToExclude = filter.tagsToExclude
        let tagNames = bridgeTask.tags
        for tag in tagsToInclude ?? [] where !tagNames.contains(tag.name) {
            return nil
        }
        for tag in tagsToExclude ?? [] where tagNames.contains(tag.name) {
            return nil
        }
    }

    return TCTask(from: bridgeTask)
}
```

Note: The filter logic should exactly match the existing behavior. Verify by comparing with the old `taskFactory` code. The tag filtering previously used `$0.get_value().toString` closures — now just string comparison against `bridgeTask.tags`.

- [ ] **Step 3: Remove Rust type helpers**

Remove these computed properties entirely:
- `rustTags` (was `[Tag?]?`)
- `rustVecOfTags` (was `RustVec<Tag>?`)
- `rustAnnotationFromObsidianNote` (was `Annotation?`)

These are replaced by:
- Tags: `task.tags?.compactMap { $0.isSynthetic() ? nil : $0.name } ?? []` in the service layer
- Annotations: direct `addAnnotation`/`removeAnnotation` calls in the service layer

- [ ] **Step 4: Commit**

```bash
git add taskchampShared/Sources/Models/TCTask.swift
git commit -m "refactor: ♻️ adapt TCTask to BridgeTaskData"
```

### Task 7: Update TaskchampionService

**Files:**
- Edit: `~/para/0-System/taskwarrior-mobile/taskchamp/taskchampShared/Sources/Services/TaskchampionService.swift`

- [ ] **Step 1: Replace import and replica type**

```swift
// OLD:
import Taskchampion

// NEW:
import TaskchampionBridge
```

Change `private var replica: Replica?` to `private var replica: BridgeReplica?`.

- [ ] **Step 2: Update setDbUrl**

```swift
// OLD:
replica = Taskchampion.new_replica_on_disk(path, true, true)
if replica == nil {
    throw TCError.genericError("Failed to create replica")
}

// NEW:
do {
    replica = try BridgeReplica.open(path: path, createIfMissing: true)
} catch {
    throw TCError.genericError("Failed to create replica: \(error)")
}
```

- [ ] **Step 3: Update getTasks and getPendingTasks and getTask**

Replace nil-checks with try/catch pattern:

```swift
// getTasks — replace:
let tasks = replica.all_tasks()
guard let tasks else { throw TCError.genericError("Query was null") }
// With:
let tasks = try replica.allTasks()

// Then replace TCTask factory calls:
// OLD: TCTask.taskFactory(from: $0, withFilter: filter)
// NEW: TCTask.taskFactory(from: $0, withFilter: filter)
// (Same signature after TCTask changes in Task 6)

// getPendingTasks — replace:
let tasks = replica.pending_tasks()
guard let tasks else { throw TCError.genericError("Query was null") }
// With:
let tasks = try replica.pendingTasks()

// OLD: tasks.map { TCTask(from: $0) }
// NEW: tasks.map { TCTask(from: $0) }
// (Same after TCTask changes)

// getTask — replace:
let task = replica.get_task(uuid)
guard let task else { throw TCError.genericError("Task not found") }
// With:
let task = try replica.getTask(uuid: uuid)
```

- [ ] **Step 4: Update createTask**

```swift
// OLD:
let task = replica.create_task(
    task.uuid.intoRustString(),
    task.description.intoRustString(),
    dueString?.intoRustString(),
    priority,
    task.project?.intoRustString(),
    task.rustVecOfTags
)
if task == nil { throw TCError.genericError("Failed to create task") }

// NEW:
let dueTimestamp: Int64? = task.due?.toBridgeTimestamp
let tagNames: [String] = task.tags?.compactMap { tag in
    tag.isSynthetic() ? nil : tag.name
} ?? []

let created = try replica.createTask(
    description: task.description,
    status: task.status.toBridgeStatus,
    priority: task.priority?.toBridgePriority,
    due: dueTimestamp,
    project: task.project,
    tags: tagNames
)

// Handle obsidian note annotation
if let note = task.obsidianNoteAnnotation {
    let annotationText = "task-note: \(note)"
    let timestamp = Int64(Date().timeIntervalSince1970.rounded())
    try replica.addAnnotation(
        uuid: created.uuid,
        description: annotationText,
        timestamp: timestamp
    )
}
```

- [ ] **Step 5: Update updateTask**

```swift
// NEW updateTask implementation:
let dueTimestamp: Int64? = task.due?.toBridgeTimestamp
let tagNames: [String] = task.tags?.compactMap { tag in
    tag.isSynthetic() ? nil : tag.name
} ?? []

let updated = try replica.updateTask(
    uuid: task.uuid,
    description: task.description,
    status: task.status.toBridgeStatus,
    priority: task.priority?.toBridgePriority,
    due: dueTimestamp,
    project: task.project,
    tags: tagNames
)

// Handle obsidian note annotation separately
if let note = task.obsidianNoteAnnotation {
    let annotationText = "task-note: \(note)"
    // Get current annotations to check for existing note
    let current = try replica.getTask(uuid: task.uuid)
    let existingNote = current.annotations.first { $0.description.hasPrefix("task-note: ") }

    if let existing = existingNote {
        // Remove old, add new (if changed)
        if existing.description != annotationText {
            try replica.removeAnnotation(uuid: task.uuid, timestamp: existing.timestamp)
            let timestamp = Int64(Date().timeIntervalSince1970.rounded())
            try replica.addAnnotation(uuid: task.uuid, description: annotationText, timestamp: timestamp)
        }
    } else {
        // Add new annotation
        let timestamp = Int64(Date().timeIntervalSince1970.rounded())
        try replica.addAnnotation(uuid: task.uuid, description: annotationText, timestamp: timestamp)
    }
}

try replica.rebuildWorkingSet()
```

Replace `if task == nil { throw ... }` patterns with the try/catch above (bridge throws on error).

- [ ] **Step 6: Replace sync_no_server calls**

Find all `replica.sync_no_server()` and replace with `try replica.rebuildWorkingSet()`.

- [ ] **Step 7: Commit**

```bash
git add taskchampShared/Sources/Services/TaskchampionService.swift
git commit -m "refactor: ♻️ adapt TaskchampionService to BridgeReplica"
```

### Task 8: Update SyncServiceProtocol

**Files:**
- Edit: `~/para/0-System/taskwarrior-mobile/taskchamp/taskchampShared/Sources/Services/SyncServiceProtocol.swift`

- [ ] **Step 1: Replace import and protocol**

```swift
// OLD:
import Taskchampion

// NEW:
import TaskchampionBridge
```

Change protocol:
```swift
// OLD:
static func sync(replica: Replica) async throws -> Bool

// NEW:
static func sync(replica: BridgeReplica) async throws -> Bool
```

Update all conforming classes to use `BridgeReplica` parameter type.

- [ ] **Step 2: Update NoSyncService**

```swift
// OLD:
public static func sync(replica: Replica) async throws -> Bool {
    return replica.sync_no_server()
}

// NEW:
public static func sync(replica: BridgeReplica) async throws -> Bool {
    try replica.rebuildWorkingSet()
    return true
}
```

- [ ] **Step 3: Update ICloudSyncService**

```swift
// OLD:
return await withCheckedContinuation { continuation in
    DispatchQueue.main.async {
        let synced = replica.sync_local_server(icloudPath)
        continuation.resume(returning: synced)
    }
}

// NEW:
try replica.syncLocal(serverDir: icloudPath)
return true
```

Remove the `DispatchQueue.main.async` + `withCheckedContinuation` wrapper — bridge calls are synchronous (they block_on internally).

- [ ] **Step 4: Update RemoteSyncService**

```swift
// OLD:
let synced = replica.sync_remote_server(
    remoteServerUrl.intoRustString(),
    remoteClientId.intoRustString(),
    remoteEncryptionSecret.intoRustString()
)

// NEW:
try replica.syncRemote(
    url: remoteServerUrl,
    clientId: remoteClientId,
    encryptionSecret: remoteEncryptionSecret
)
return true
```

Remove the `DispatchQueue.main.async` + `withCheckedContinuation` wrapper.

- [ ] **Step 5: Update GcpSyncService**

```swift
// NEW:
try replica.syncGcp(
    bucket: bucket,
    credentialPath: getGcpCredentialPath(),
    encryptionSecret: encryptionSecret
)
return true
```

Remove the `DispatchQueue.main.async` + `withCheckedContinuation` wrapper.

- [ ] **Step 6: Update AwsSyncService**

```swift
// NEW:
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

Remove the `DispatchQueue.main.async` + `withCheckedContinuation` wrapper.

- [ ] **Step 7: Commit**

```bash
git add taskchampShared/Sources/Services/SyncServiceProtocol.swift
git commit -m "refactor: ♻️ adapt sync services to BridgeReplica"
```

---

## Chunk 4: Build Verification

### Task 9: Generate Xcode project and build

**Files:**
- No file changes — verification only

Work from: `~/para/0-System/taskwarrior-mobile/taskchamp`

- [ ] **Step 1: Run tuist generate**

```bash
cd ~/para/0-System/taskwarrior-mobile/taskchamp
tuist generate
```

Expected: Xcode project generated without errors.

If there are dependency resolution errors, check:
- Does `../bridge/Package.swift` exist and define `TaskchampionBridge` product?
- Does `../bridge/output/TaskchampionBridge.xcframework` exist?
- Are the Swift binding files in `../bridge/output/swift/`?

- [ ] **Step 2: Build in Xcode**

```bash
xcodebuild -project taskchamp.xcodeproj -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Or open Xcode and build manually. Fix any compilation errors — likely:
- Missing imports
- Type mismatches in places the plan didn't cover
- Method signature changes

- [ ] **Step 3: Fix remaining compilation errors**

If the build has errors, fix them one file at a time. Common issues:
- Widget extension may also import Taskchampion — check `taskchampWidget/Sources/`
- Any file not covered by the plan that imports `Taskchampion`
- Tuist may need `tuist install` before `tuist generate` for external dependencies

Find all remaining references:
```bash
grep -rn "import Taskchampion\b" taskchamp/ taskchampShared/ taskchampWidget/ --include="*.swift"
```

Fix each one.

- [ ] **Step 4: Run in Simulator**

Launch the app in the iOS Simulator. Verify:
- App launches without crash
- Task list displays (may be empty if no database)
- Create a task → appears in list
- Edit a task → changes persist
- Complete a task → status updates
- Delete a task → removed from list

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: 🐛 resolve build errors from bridge migration"
```

- [ ] **Step 6: Push**

```bash
git push origin feat/bridge-integration
```
