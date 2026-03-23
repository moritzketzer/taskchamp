# TaskChamp AlarmKit Integration — Implementation Plan

> **For agentic workers:** REQUIRED: Use subagent-driven-development (if subagents available) or executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tasks tagged `+alarm` with a due date trigger a real system alarm (AlarmKit) instead of a standard notification.

**Architecture:** New `AlarmService` in `taskchampShared/Sources/Services/` handles AlarmKit scheduling/cancellation. The existing `NotificationService` skips tasks with `+alarm` tag. UI views get an "Alarm" toggle that adds/removes the `+alarm` tag. The `TCTask` model gets a computed `hasAlarm` property.

**Tech Stack:** Swift, AlarmKit (iOS 26+), SwiftUI, Tuist (Project.swift)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `taskchampShared/Sources/Services/AlarmService.swift` | AlarmKit authorization, schedule/cancel alarms, reconcile after sync |
| Modify | `taskchampShared/Sources/Models/TCTask.swift` | Add `hasAlarm` computed property |
| Modify | `taskchampShared/Sources/Services/NotificationService.swift` | Skip `+alarm` tasks in `createReminderForTask(s)` |
| Modify | `taskchamp/Sources/View/CreateTaskView.swift` | Add alarm toggle |
| Modify | `taskchamp/Sources/View/EditTaskView.swift` | Add alarm toggle state |
| Modify | `taskchamp/Sources/View/EditTaskView-Ext.swift` | Wire alarm on create/update/delete |
| Modify | `taskchamp/Sources/View/TaskListView-Ext.swift` | Call AlarmService in `setupNotifications()` and sync flow |
| Modify | `Project.swift` | Add `NSAlarmKitUsageDescription` to Info.plist, bump deployment target to iOS 26 |

---

## Chunk 1: Model + AlarmService Foundation

### Task 1: Add `hasAlarm` computed property to TCTask

**Files:**
- Modify: `taskchampShared/Sources/Models/TCTask.swift`

- [ ] **Step 1: Add computed property**

Add after the existing `hasNote` computed property (~line 210):

```swift
public var hasAlarm: Bool {
    tags?.contains(where: { $0.name == "alarm" }) ?? false
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/para/0-System/taskchamp && tuist generate 2>&1 | tail -5`
Then: `xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add taskchampShared/Sources/Models/TCTask.swift
git commit -m "feat: add hasAlarm computed property to TCTask"
```

### Task 2: Create AlarmService

**Files:**
- Create: `taskchampShared/Sources/Services/AlarmService.swift`

- [ ] **Step 1: Create the service file**

```swift
import Foundation
import AlarmKit

@MainActor
public class AlarmService {
    public static let shared = AlarmService()
    private let manager = AlarmManager.shared

    private init() {}

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        let status = await manager.authorizationStatus
        switch status {
        case .notDetermined:
            do {
                try await manager.requestAuthorization()
                return true
            } catch {
                print("AlarmKit authorization failed: \(error)")
                return false
            }
        case .authorized:
            return true
        default:
            return false
        }
    }

    // MARK: - Schedule

    public func scheduleAlarm(for task: TCTask) async {
        guard task.hasAlarm,
              let due = task.due,
              due > Date()
        else { return }

        let authorized = await requestAuthorization()
        guard authorized else { return }

        let alert = AlarmPresentation.Alert(
            title: task.description,
            stopButton: .init(label: "Done")
        )

        let presentation = AlarmPresentation.templateBased(alert: alert)

        let alarm = Alarm(
            id: task.uuid,
            schedule: .oneTime(date: due),
            presentation: presentation
        )

        do {
            try await manager.schedule(alarm)
            print("AlarmKit: scheduled alarm for task \(task.uuid) at \(due)")
        } catch {
            print("AlarmKit: failed to schedule alarm: \(error)")
        }
    }

    // MARK: - Cancel

    public func cancelAlarm(for taskUUID: String) async {
        do {
            try await manager.cancel(alarmWith: taskUUID)
            print("AlarmKit: cancelled alarm for task \(taskUUID)")
        } catch {
            print("AlarmKit: failed to cancel alarm for \(taskUUID): \(error)")
        }
    }

    // MARK: - Reconcile

    /// Called after sync. Schedules alarms for +alarm tasks with future due dates,
    /// cancels alarms for tasks that no longer qualify.
    public func reconcileAlarms(tasks: [TCTask]) async {
        let scheduledAlarms = await manager.scheduledAlarms
        let scheduledIDs = Set(scheduledAlarms.map(\.id))

        let alarmTasks = tasks.filter { $0.hasAlarm && $0.due != nil && ($0.due ?? .distantPast) > Date() && $0.status == .pending }
        let alarmTaskIDs = Set(alarmTasks.map(\.uuid))

        // Cancel alarms that no longer qualify
        for id in scheduledIDs where !alarmTaskIDs.contains(id) {
            await cancelAlarm(for: id)
        }

        // Schedule new alarms
        for task in alarmTasks where !scheduledIDs.contains(task.uuid) {
            await scheduleAlarm(for: task)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

Note: AlarmKit API surface may differ from what's documented. If compilation fails, check `AlarmManager` API via Xcode's generated interface: `xcodebuild docbuild` or read the AlarmKit header. Adjust method names, initializers, and types as needed. The logic stays the same — only the API surface may need adaptation.

- [ ] **Step 3: Commit**

```bash
git add taskchampShared/Sources/Services/AlarmService.swift
git commit -m "feat: add AlarmService for AlarmKit alarm scheduling"
```

### Task 3: Update Project.swift

**Files:**
- Modify: `Project.swift`

- [ ] **Step 1: Add NSAlarmKitUsageDescription to infoPlist**

In `Project.swift`, in the main `taskchamp` target's `infoPlist: .extendingDefault(with: [...])`, add:

```swift
"NSAlarmKitUsageDescription": "TaskChamp uses alarms to alert you about urgent tasks at their due time."
```

- [ ] **Step 2: Update deployment target**

Change `deploymentTargets: .iOS("17.0")` to `deploymentTargets: .iOS("26.0")` for the main `taskchamp` target. Leave other targets at 17.0 unless they also import AlarmKit.

Note: Raising the deployment target to iOS 26 means the app won't run on older iOS versions. If the upstream project needs to support iOS 17+, wrap AlarmKit usage in `if #available(iOS 26, *)` checks instead and keep the deployment target at 17.0. For our fork, iOS 26 is fine.

- [ ] **Step 3: Verify it compiles**

Run: `tuist generate && xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

- [ ] **Step 4: Commit**

```bash
git add Project.swift
git commit -m "build: add AlarmKit usage description and update deployment target"
```

---

## Chunk 2: NotificationService Guard + UI Integration

### Task 4: Skip +alarm tasks in NotificationService

**Files:**
- Modify: `taskchampShared/Sources/Services/NotificationService.swift`

- [ ] **Step 1: Guard in createReminderForTask**

At the top of `createReminderForTask(task:)`, add:

```swift
guard !task.hasAlarm else {
    return
}
```

- [ ] **Step 2: Guard in createReminderForTasks**

In `createReminderForTasks(tasks:)`, update the `for` loop filter:

Change:
```swift
for task in tasks where !notifTaskIds.contains(task.uuid) && task.due != nil && (task.due ?? Date()) > Date() {
```

To:
```swift
for task in tasks where !task.hasAlarm && !notifTaskIds.contains(task.uuid) && task.due != nil && (task.due ?? Date()) > Date() {
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

- [ ] **Step 4: Commit**

```bash
git add taskchampShared/Sources/Services/NotificationService.swift
git commit -m "fix: skip +alarm tasks in NotificationService to avoid double alerts"
```

### Task 5: Add alarm toggle to CreateTaskView

**Files:**
- Modify: `taskchamp/Sources/View/CreateTaskView.swift`

- [ ] **Step 1: Add alarm state variable**

After `@State private var priority: TCTask.Priority = .none`, add:

```swift
@State private var isAlarm = false
```

- [ ] **Step 2: Add toggle in the form**

In the `Section` that contains the Priority picker and AddTagButton, add after AddTagButton:

```swift
if didSetDate && didSetTime {
    Toggle(isOn: $isAlarm) {
        Label("Alarm", systemImage: "alarm.fill")
    }
}
```

- [ ] **Step 3: Wire alarm tag into task creation**

In the "Done" button action, before the `TCTask(...)` initializer, add alarm tag logic:

```swift
var finalTags = tags
if isAlarm {
    let alarmTag = TCTag(name: "alarm")
    if !finalTags.contains(where: { $0.name == "alarm" }) {
        finalTags.append(alarmTag)
    }
}
```

Then update the `TCTask` initializer to use `finalTags` instead of `tags`:

```swift
let task = TCTask(
    uuid: UUID().uuidString,
    project: project.isEmpty ? nil : project,
    description: description,
    status: status,
    priority: priority == .none ? nil : priority,
    due: finalDate,
    tags: finalTags.isEmpty ? nil : finalTags
)
```

- [ ] **Step 4: Wire AlarmService after task creation**

After the existing `NotificationService.shared.createReminderForTask(task: task)` line, add:

```swift
if task.hasAlarm {
    Task {
        await AlarmService.shared.scheduleAlarm(for: task)
    }
}
```

- [ ] **Step 5: Also handle NLP input**

In the `onChange(of: nlpInput)` handler, after tag parsing, add alarm detection:

```swift
isAlarm = nlpTask.tags?.contains(where: { $0.name == "alarm" }) ?? false
```

- [ ] **Step 6: Verify it compiles**

Run: `xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

- [ ] **Step 7: Commit**

```bash
git add taskchamp/Sources/View/CreateTaskView.swift
git commit -m "feat: add alarm toggle to CreateTaskView"
```

### Task 6: Add alarm toggle to EditTaskView

**Files:**
- Modify: `taskchamp/Sources/View/EditTaskView.swift`
- Modify: `taskchamp/Sources/View/EditTaskView-Ext.swift`

- [ ] **Step 1: Add alarm state variable to EditTaskView**

After `@State var priority: TCTask.Priority = .none`, add:

```swift
@State var isAlarm = false
```

- [ ] **Step 2: Initialize from task in init()**

In `init(task:)`, after `tags = task.tags ?? []`, add:

```swift
isAlarm = task.hasAlarm
```

- [ ] **Step 3: Add toggle to EditTaskView form**

In the form section with Priority picker and AddTagButton (find it in EditTaskView.swift body), add:

```swift
if didSetDate && didSetTime {
    Toggle(isOn: $isAlarm) {
        Label("Alarm", systemImage: "alarm.fill")
    }
}
```

- [ ] **Step 4: Include didChange detection**

Add alarm state to the `didChange` computed property:

```swift
task.hasAlarm != isAlarm
```

(Add with `||` to the existing expression.)

- [ ] **Step 5: Wire alarm tag in updateTask() (EditTaskView-Ext.swift)**

In `updateTask()`, before `let task = TCTask(...)`, add:

```swift
var finalTags = tags ?? []
if isAlarm {
    if !finalTags.contains(where: { $0.name == "alarm" }) {
        finalTags.append(TCTag(name: "alarm"))
    }
} else {
    finalTags.removeAll(where: { $0.name == "alarm" })
}
```

Update the TCTask initializer to use `finalTags.isEmpty ? nil : finalTags` for tags.

- [ ] **Step 6: Wire AlarmService in updateTask()**

After `NotificationService.shared.createReminderForTask(task: task)`, add:

```swift
Task {
    if task.hasAlarm {
        await AlarmService.shared.scheduleAlarm(for: task)
    } else {
        await AlarmService.shared.cancelAlarm(for: task.uuid)
    }
}
```

- [ ] **Step 7: Wire AlarmService in deleteTask()**

After `NotificationService.shared.deleteReminderForTask(task: task)`, add:

```swift
Task {
    await AlarmService.shared.cancelAlarm(for: task.uuid)
}
```

- [ ] **Step 8: Wire AlarmService in handleTaskActionTap()**

After the existing notification handling in `handleTaskActionTap()`, add:

```swift
if (newStatus == .completed) || (newStatus == .deleted) {
    Task { await AlarmService.shared.cancelAlarm(for: task.uuid) }
} else if task.hasAlarm {
    Task { await AlarmService.shared.scheduleAlarm(for: task) }
}
```

- [ ] **Step 9: Verify it compiles**

Run: `xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

- [ ] **Step 10: Commit**

```bash
git add taskchamp/Sources/View/EditTaskView.swift taskchamp/Sources/View/EditTaskView-Ext.swift
git commit -m "feat: add alarm toggle to EditTaskView with bidirectional tag sync"
```

---

## Chunk 3: Sync Reconciliation + Final Wiring

### Task 7: Wire AlarmService into sync flow

**Files:**
- Modify: `taskchamp/Sources/View/TaskListView-Ext.swift`

- [ ] **Step 1: Add AlarmKit import**

At the top, add:

```swift
import AlarmKit
```

(This may not be needed if AlarmService handles it — check if it compiles without.)

- [ ] **Step 2: Add alarm reconciliation to setupNotifications()**

In `setupNotifications()`, after the `await NotificationService.shared.createReminderForTasks(tasks: pending)` line, add:

```swift
await AlarmService.shared.reconcileAlarms(tasks: pending)
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`

- [ ] **Step 4: Commit**

```bash
git add taskchamp/Sources/View/TaskListView-Ext.swift
git commit -m "feat: reconcile AlarmKit alarms after sync"
```

### Task 8: End-to-end verification

- [ ] **Step 1: Full clean build**

```bash
cd ~/para/0-System/taskchamp
tuist clean
tuist generate
xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' clean build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run tests**

```bash
xcodebuild -scheme taskchamp -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: Tests pass (existing tests should not break)

- [ ] **Step 3: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: address build issues from AlarmKit integration"
```

(Skip if clean build succeeded without fixups.)
