import Foundation
import CoreLocation

final class UserStore: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = UserStore()

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var _coordinate: CLLocationCoordinate2D?
    private var _downloadMbps: Double?
    private var _uploadMbps: Double?

    var coordinate: CLLocationCoordinate2D {
        lock.lock(); defer { lock.unlock() }
        return _coordinate ?? CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
    }

    var hasFix: Bool {
        lock.lock(); defer { lock.unlock() }
        return _coordinate != nil
    }

    var downloadMbps: Double? {
        lock.lock(); defer { lock.unlock() }
        return _downloadMbps
    }

    var uploadMbps: Double? {
        lock.lock(); defer { lock.unlock() }
        return _uploadMbps
    }

    func updateSpeed(downloadMbps: Double?, uploadMbps: Double?) {
        lock.lock()
        _downloadMbps = downloadMbps
        _uploadMbps = uploadMbps
        lock.unlock()
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissions() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        lock.lock(); _coordinate = latest.coordinate; lock.unlock()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // no-op for now
    }
}
