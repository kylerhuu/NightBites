import CoreLocation
import Observation
import UIKit

@Observable
final class LocationAccessManager: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    var authorizationStatus: CLAuthorizationStatus
    var latestCoordinate: CLLocationCoordinate2D?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        self.manager.delegate = self
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Always allowed"
        case .authorizedWhenInUse:
            return "Allowed while using app"
        @unknown default:
            return "Unknown"
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermission() {
        AppTelemetry.track(event: "location_permission_requested")
        manager.requestWhenInUseAuthorization()
    }

    func refreshLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        AppTelemetry.track(event: "location_permission_updated", metadata: ["status": statusDescription])
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppTelemetry.track(error: "location_update_failed", metadata: ["message": error.localizedDescription])
    }
}
