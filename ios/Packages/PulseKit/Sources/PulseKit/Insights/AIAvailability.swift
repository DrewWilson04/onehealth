import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether on-device Apple Intelligence (Foundation Models) can be used.
/// Re-checked at every launch and whenever the app becomes active, because
/// users can enable Apple Intelligence (or the model can finish downloading)
/// at any time. When unavailable, the AI insights feature is hidden entirely.
@MainActor
@Observable
public final class AIAvailability {
    public private(set) var isAvailable = false
    public init() { refresh() }

    public func refresh() {
        #if canImport(FoundationModels) && !os(watchOS)
        if case .available = SystemLanguageModel.default.availability {
            isAvailable = true
        } else {
            isAvailable = false
        }
        #else
        isAvailable = false
        #endif
        PulseKitConfig.aiSupportedHint = isAvailable
    }
}
