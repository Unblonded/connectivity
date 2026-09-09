//
//  ConnectivitySample.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import Foundation
import CoreLocation

struct ConnectivitySample: Identifiable, Codable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var signal: Int          // 0...5
    var mbUp: Double?
    var mbDown: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var signalTier: SignalTier {
        switch signal {
        case 4...5: return .good
        case 2...3: return .poor
        default:    return .dead
        }
    }
}

enum SignalTier {
    case good, poor, dead

    var color: Color {
        switch self {
        case .good: return Color(red: 0.09, green: 0.78, blue: 0.48) // --good
        case .poor: return Color(red: 1.00, green: 0.60, blue: 0.30) // --poor
        case .dead: return Color(red: 1.00, green: 0.42, blue: 0.42) // --dead
        }
    }
}

import SwiftUI
