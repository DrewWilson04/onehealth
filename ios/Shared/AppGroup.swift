import Foundation
import PulseCore

/// App Group shared container (app ↔ widgets ↔ watch complications).
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "PBAppGroup") as? String) ?? ""
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func readSnapshot() -> WidgetSnapshot? {
        snapshotURL.flatMap(WidgetSnapshot.read(from:))
    }

    static func writeSnapshot(_ s: WidgetSnapshot) {
        guard let url = snapshotURL else { return }
        try? s.write(to: url)
        // Readable after first unlock so lock-screen widgets work.
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
    }
}
