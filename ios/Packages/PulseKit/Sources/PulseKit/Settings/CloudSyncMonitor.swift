import Foundation
import CloudKit
import Observation

/// iCloud account availability for the settings sync UI.
@MainActor
@Observable
public final class CloudSyncMonitor {
    public enum Account: Equatable {
        case unknown, available, noAccount, restricted, temporarilyUnavailable, error(String)
        public var description: String {
            switch self {
            case .unknown: return "Checking…"
            case .available: return "On"
            case .noAccount: return "Sign in to iCloud to sync settings"
            case .restricted: return "iCloud is restricted on this device"
            case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
            case .error(let e): return e
            }
        }
    }

    public private(set) var account: Account = .unknown
    private let containerID: String?

    public init(containerID: String?) {
        self.containerID = containerID
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    public func refresh() async {
        guard let id = containerID, !id.isEmpty else { account = .error("iCloud container not configured"); return }
        do {
            switch try await CKContainer(identifier: id).accountStatus() {
            case .available: account = .available
            case .noAccount: account = .noAccount
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            case .couldNotDetermine: account = .unknown
            @unknown default: account = .unknown
            }
        } catch {
            account = .error(error.localizedDescription)
        }
    }
}
