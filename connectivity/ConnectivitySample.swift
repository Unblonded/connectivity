//
//  ConnectivitySample.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import Foundation
import CoreLocation
import SwiftUI

struct ConnectivitySample: Identifiable, Codable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var mbUp: Double?
    var mbDown: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var score: Int {
        speedScore(d: mbDown ?? 0, u: mbUp ?? 0)
    }

    var signalColor: Color {
        colorForScore(score)
    }
}

func speedScore(d: Double, u: Double) -> Int {
    let downWeight = 0.7
    let upWeight = 0.3

    let maxDown = 40.0   // was 100 — 40 Mbps down now scores ~100
    let maxUp = 15.0     // was 50 — 15 Mbps up now scores ~100

    let downScore = log10(1 + min(d, maxDown)) / log10(1 + maxDown)
    let upScore = log10(1 + min(u, maxUp)) / log10(1 + maxUp)

    let combined = (downScore * downWeight) + (upScore * upWeight)
    return Int((combined * 100).rounded())
}

// dead (red) -> poor (orange) -> good (green), interpolated continuously
func colorForScore(_ score: Int) -> Color {
    let t = max(0.0, min(1.0, Double(score) / 100.0))

    let dead  = (r: 1.00, g: 0.42, b: 0.42)
    let poor  = (r: 1.00, g: 0.60, b: 0.30)
    let good  = (r: 0.09, g: 0.78, b: 0.48)

    let (from, to, localT): ((Double, Double, Double), (Double, Double, Double), Double) =
        t < 0.5
        ? ((dead.r, dead.g, dead.b), (poor.r, poor.g, poor.b), t / 0.5)
        : ((poor.r, poor.g, poor.b), (good.r, good.g, good.b), (t - 0.5) / 0.5)

    let r = from.0 + (to.0 - from.0) * localT
    let g = from.1 + (to.1 - from.1) * localT
    let b = from.2 + (to.2 - from.2) * localT

    return Color(red: r, green: g, blue: b)
}
