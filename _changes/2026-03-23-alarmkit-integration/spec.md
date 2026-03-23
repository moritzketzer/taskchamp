# TaskChamp AlarmKit Integration

## Summary

Add AlarmKit support to TaskChamp so that tasks tagged `+alarm` with a due date trigger a real system alarm (like the iPhone Clock app) instead of a standard notification.

## Trigger Mechanism

- **CLI path:** User adds `+alarm` tag in TaskWarrior (e.g., `task add "Meeting prep" due:today+14:00 +alarm`). On next sync, TaskChamp detects the tag and schedules an AlarmKit alarm.
- **App path:** Toggle "Alarm" in TaskChamp's Create/Edit Task UI. Setting the toggle adds the `+alarm` tag to the task (bidirectional — visible in TaskWarrior).

## Behavior

- On each sync, scan all pending tasks for `+alarm` tag + future due date → schedule AlarmKit alarm at due time.
- Alarm uses system default tone with AlarmKit's built-in Snooze/Stop UI.
- When a task is completed, deleted, or the `+alarm` tag is removed → cancel the corresponding alarm.
- Tasks with `+alarm` but no due date → no alarm scheduled (silently ignored).
- Tasks with `+alarm` that already have a scheduled alarm with matching due date → no-op (no duplicate).

## Architecture

### New: `AlarmService`

Sits alongside the existing `NotificationService` in `taskchampShared/Sources/Services/`.

Responsibilities:
- Request AlarmKit authorization on first use.
- Schedule/cancel alarms keyed by task UUID.
- Provide a method to reconcile alarms with current task state (called after sync).

### Interaction with `NotificationService`

Tasks with `+alarm` tag should use AlarmKit instead of `UNNotification`. The existing `createReminderForTask` should skip tasks that have the `+alarm` tag to avoid double alerts.

### UI Changes

- `CreateTaskView` and `EditTaskView`: add an "Alarm" toggle. When enabled, adds `+alarm` to task tags. When disabled, removes it. Only visible/enabled when a due date is set.
- Toggle state derived from presence of `+alarm` in task tags (no separate local state).

### Info.plist

Add `NSAlarmKitUsageDescription` with a user-facing explanation, e.g.: "TaskChamp uses alarms to alert you about urgent tasks at their due time."

## Scope

### In scope
- AlarmKit alarm scheduling/cancellation based on `+alarm` tag
- Bidirectional tag sync (UI toggle ↔ TaskWarrior tag)
- Permission request flow
- Skip `+alarm` tasks in existing notification path

### Out of scope
- Separate alarm time field (alarm fires at due time)
- Custom alarm tones
- Lead time / early reminder
- Widget alarm indicators

## Dependencies

- AlarmKit framework (iOS 26+)
- Xcode 26+
