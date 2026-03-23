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

        let alarmTasks = tasks.filter {
            $0.hasAlarm && $0.due != nil && ($0.due ?? .distantPast) > Date() && $0.status == .pending
        }
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
