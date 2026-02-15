import Foundation
import CoreLocation
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "LocationManager")

/// Manages location services for the Apple Watch app.
/// Fetches the user's current location when a seizure alert is triggered.

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Shared singleton so MainView and SettingsView use the same location state
    static let shared = LocationManager()

    // MARK: - Published State

    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?

    // MARK: - Private

    private let locationManager = CLLocationManager()

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Public API

    /// Request location permissions (call on first launch)
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Fetch a single location update (used when alert triggers)
    func requestCurrentLocation() {
        locationError = nil
        locationManager.requestLocation()
    }

    /// Start continuous location updates (optional, for higher accuracy)
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        logger.info("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
        logger.error("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            logger.info("Location authorized")
        case .denied, .restricted:
            locationError = "Location access denied. Please enable in Settings."
            logger.warning("Location access denied")
        case .notDetermined:
            logger.info("Location authorization not yet determined")
        @unknown default:
            break
        }
    }
}
