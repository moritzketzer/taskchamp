import Foundation
import TaskchampionBridge

// MARK: - Status Mapping

extension TaskStatus {
    var toAppStatus: TCTask.Status {
        switch self {
        case .pending: return .pending
        case .completed: return .completed
        case .deleted: return .deleted
        }
    }
}

extension TCTask.Status {
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
    var toAppPriority: TCTask.Priority {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

extension TCTask.Priority {
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
    var toBridgeTimestamp: Int64 { Int64(timeIntervalSince1970.rounded()) }
}

extension Int64 {
    var toDate: Date { Date(timeIntervalSince1970: TimeInterval(self)) }
}
