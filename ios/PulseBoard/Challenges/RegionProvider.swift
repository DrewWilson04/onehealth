import Foundation
import CoreLocation
import Observation

/// Coarse region for local challenges. Uses reduced-accuracy location and
/// keeps ONLY "City, Region" text — coordinates are discarded immediately.
@MainActor
@Observable
final class RegionProvider: NSObject, CLLocationManagerDelegate {
    var region: String?
    var error: String?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: error = "Location access is off. You can type your city instead."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways { m.requestLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let marks = try? await CLGeocoder().reverseGeocodeLocation(loc)
            if let p = marks?.first {
                self.region = [p.locality ?? p.subAdministrativeArea, p.administrativeArea ?? p.country].compactMap { $0 }.joined(separator: ", ")
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.error = error.localizedDescription }
    }
}
