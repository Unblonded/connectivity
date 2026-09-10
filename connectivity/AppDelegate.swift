//
//  AppDelegate.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//

import UIKit
import CoreLocation

class AppDelegate: NSObject, UIApplicationDelegate, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Background task registration
        BackgroundTaskManager.shared.register()
        BackgroundTaskManager.shared.schedule()
        
        // Location setup
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        
        return true
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.startUpdatingLocation()
        case .authorizedWhenInUse:
            // Not enough — background location won't work
            print("Need 'Always' permission for background updates")
        case .denied, .restricted:
            print("Location permission denied")
        default:
            break
        }
    }
}
