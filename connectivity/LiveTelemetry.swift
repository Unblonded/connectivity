//
//  LiveTelemetry.swift
//  connectivity
//
//  Observable state for the speed test loop, so the UI can show what is
//  happening right now instead of polling `UserStore` once a second.
//
import Foundation
import Observation

enum TelemetryPhase: Equatable {
    case idle
    case download
    case upload
    case wifiPaused

    var isMeasuring: Bool {
        self == .download || self == .upload
    }

    var label: String {
        switch self {
        case .idle: return "Standing by"
        case .download: return "Measuring download"
        case .upload: return "Measuring upload"
        case .wifiPaused: return "Paused on Wi-Fi"
        }
    }
}

struct TelemetryPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let score: Int
    let downloadMbps: Double
    let uploadMbps: Double
}

@MainActor
@Observable
final class LiveTelemetry {
    static let shared = LiveTelemetry()

    private(set) var phase: TelemetryPhase = .idle
    private(set) var downloadMbps: Double?
    private(set) var uploadMbps: Double?
    private(set) var lastTestDate: Date?
    private(set) var history: [TelemetryPoint] = []
    private(set) var completedTests = 0

    /// How many readings the sparkline keeps.
    static let historyLimit = 40

    private init() {}

    var latestScore: Int? {
        history.last?.score
    }

    var averageScore: Int? {
        guard !history.isEmpty else { return nil }
        return history.map(\.score).reduce(0, +) / history.count
    }

    func setPhase(_ phase: TelemetryPhase) {
        self.phase = phase
    }

    func record(downloadMbps: Double?, uploadMbps: Double?) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        lastTestDate = Date()
        completedTests += 1
        phase = .idle

        // A failed leg would otherwise plot as a dead zone.
        guard downloadMbps != nil || uploadMbps != nil else { return }

        let down = downloadMbps ?? 0
        let up = uploadMbps ?? 0
        history.append(
            TelemetryPoint(date: Date(), score: speedScore(d: down, u: up), downloadMbps: down, uploadMbps: up)
        )
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    func reset() {
        phase = .idle
        downloadMbps = nil
        uploadMbps = nil
        lastTestDate = nil
        history = []
        completedTests = 0
    }
}
