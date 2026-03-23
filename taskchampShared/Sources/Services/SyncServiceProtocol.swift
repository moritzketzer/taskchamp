import SwiftUI
import TaskchampionBridge

// MARK: - SyncServiceProtocol

public protocol SyncServiceProtocol {
    static var syncServiceType: TaskchampionService.SyncType { get }
    static var settingName: String { get }
    static var errorTitle: String { get }
    static var errorMessage: String { get }
    static func sync(replica: BridgeReplica) async throws -> Bool
    static func isAvailable() -> Bool
}

// MARK: - NoSyncService

public class NoSyncService: SyncServiceProtocol {
    public static let syncServiceType: TaskchampionService.SyncType = .none
    public static let settingName = "No Sync Service"
    public static let errorTitle = "Unexpected Error"
    public static let errorMessage = "Please try again later"

    private init() {}

    public static func isAvailable() -> Bool {
        return true
    }

    @MainActor
    public static func sync(replica: BridgeReplica) async throws -> Bool {
        try replica.rebuildWorkingSet()
        return true
    }
}

// MARK: - ICloudSyncService

public class ICloudSyncService: SyncServiceProtocol {
    public static let syncServiceType: TaskchampionService.SyncType = .local
    public static let settingName = "iCloud Sync"
    public static let errorTitle = "iCloud Required"
    public static let errorMessage =
        "In order to use Taskchamp with iCloud Sync, you require to have an iCloud account and iCloud Drive enabled"

    private init() {}

    public static func isAvailable() -> Bool {
        return FileService.shared.isICloudAvailable()
    }

    @MainActor
    public static func sync(replica: BridgeReplica) async throws -> Bool {
        let icloudPath = try FileService.shared.getDestinationPathForICloudServer()
        try replica.syncLocal(serverDir: icloudPath)
        return true
    }
}

public class RemoteSyncService: SyncServiceProtocol {
    public static let syncServiceType: TaskchampionService.SyncType = .remote
    public static let settingName = "Taskchampion Sync Server"
    public static let errorTitle = "There was an error"
    public static let errorMessage =
        "Make sure that you have the `taskchampion-sync-server` running"

    private init() {}

    public static func getRemoteServerUrl() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .remoteServerUrl)
        return value
    }

    public static func getRemoteClientId() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .remoteServerClientId)
        return value
    }

    public static func getRemoteEncryptionSecret() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .remoteServerEncryptionSecret)
        return value
    }

    public static func isAvailable() -> Bool {
        return getRemoteServerUrl() != nil &&
            getRemoteClientId() != nil &&
            getRemoteEncryptionSecret() != nil
    }

    @MainActor
    public static func sync(replica: BridgeReplica) async throws -> Bool {
        // swiftlint:disable all
        guard let remoteServerUrl = getRemoteServerUrl(),
              let remoteClientId = getRemoteClientId(),
              let remoteEncryptionSecret = getRemoteEncryptionSecret() else
        {
            // swiftlint:enable all
            throw TCError.genericError("Remote server configuration is incomplete")
        }

        try replica.syncRemote(
            url: remoteServerUrl,
            clientId: remoteClientId,
            encryptionSecret: remoteEncryptionSecret
        )
        return true
    }
}

public class GcpSyncService: SyncServiceProtocol {
    public static let syncServiceType: TaskchampionService.SyncType = .gcp
    public static let settingName = "Google Cloud Platform"
    public static let errorTitle = "There was an error"
    public static let errorMessage =
        "Make sure that you have the correct GCP configuration"

    private init() {}

    public static func getGcpBucket() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .gcpServerBucket)
        return value
    }

    public static func getGcpCredentialPath() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .gcpServerCredentialPath)
        return value
    }

    public static func getGcpEncryptionSecret() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .gcpServerEncryptionSecret)
        return value
    }

    public static func isAvailable() -> Bool {
        return getGcpBucket() != nil &&
            getGcpEncryptionSecret() != nil
    }

    @MainActor
    public static func sync(replica: BridgeReplica) async throws -> Bool {
        // swiftlint:disable all
        guard let bucket = getGcpBucket(),
              let encryptionSecret = getGcpEncryptionSecret() else
        {
            // swiftlint:enable all
            throw TCError.genericError("GCP configuration is incomplete")
        }

        try replica.syncGcp(
            bucket: bucket,
            credentialPath: getGcpCredentialPath(),
            encryptionSecret: encryptionSecret
        )
        return true
    }
}

public class AwsSyncService: SyncServiceProtocol {
    public static let syncServiceType: TaskchampionService.SyncType = .aws
    public static let settingName = "Amazon Web Services"
    public static let errorTitle = "There was an error"
    public static let errorMessage =
        "Make sure that you have the correct AWS configuration"

    public static func getAwsBucket() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .awsServerBucket)
        return value
    }

    public static func getAwsRegion() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .awsServerRegion)
        return value
    }

    public static func getAwsAccessKeyId() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .awsServerAccessKeyId)
        return value
    }

    public static func getAwsSecretAccessKey() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .awsServerSecretAccessKey)
        return value
    }

    public static func getAwsEncryptionSecret() -> String? {
        let value: String? = UserDefaultsManager.shared.getValue(forKey: .awsServerEncryptionSecret)
        return value
    }

    private init() {}

    public static func isAvailable() -> Bool {
        return getAwsBucket() != nil &&
            getAwsRegion() != nil &&
            getAwsAccessKeyId() != nil &&
            getAwsSecretAccessKey() != nil &&
            getAwsEncryptionSecret() != nil
    }

    @MainActor
    public static func sync(replica: BridgeReplica) async throws -> Bool {
        // swiftlint:disable all
        guard let bucket = getAwsBucket(),
              let region = getAwsRegion(),
              let accessKeyId = getAwsAccessKeyId(),
              let secretAccessKey = getAwsSecretAccessKey(),
              let encryptionSecret = getAwsEncryptionSecret() else
        {
            // swiftlint:enable all
            throw TCError.genericError("AWS configuration is incomplete")
        }

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
    }
}
