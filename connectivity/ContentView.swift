//
//  ContentView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//

import SwiftUI
import CoreLocation
import Combine

struct ContentView: View {
    @State private var circles: [SignalCircle] = []
    @State private var startPoint: CLLocationCoordinate2D?
    @State private var endPoint: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var lastLocation: CLLocation?
    @State private var hasCenteredOnFix = false
    
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let speedTestTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header

                    ConnectivityMapView(
                        startPoint: $startPoint,
                        endPoint: $endPoint,
                        circles: $circles,
                        routeCoordinates: routeCoordinates
                    )
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(12)

                    sidebar
                        .padding(12)
                }
                .padding(.bottom, 90) // room for the pill
            }

            userInfoPill
        }
        .onReceive(refreshTimer) { _ in
            if !hasCenteredOnFix && UserStore.shared.hasFix {
                hasCenteredOnFix = true
                generateTestCircles()
            }
            lastLocation = CLLocation(
                latitude: UserStore.shared.coordinate.latitude,
                longitude: UserStore.shared.coordinate.longitude
            )
        }
        .onAppear {
            UserStore.shared.requestPermissions()
            UserStore.shared.startUpdates()
            generateTestCircles()
        }
        .onReceive(speedTestTimer) { _ in
            BackgroundTaskManager.shared.runSpeedTestAndLog()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 0.016, green: 0.165, blue: 0.227))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(AppTheme.accent)
                        .font(.system(size: 14))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Connectivity").bold()
                Text("Find and avoid low-signal areas")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
        }
        .padding()
        .background(Color(red: 0.024, green: 0.055, blue: 0.078).opacity(0.98))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Route Builder").font(.headline)
                Text("Tap map to set Start and End points.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                HStack {
                    Button("Generate Route") { generateRoute() }
                        .buttonStyle(.borderedProminent)
                    Button("Clear") {
                        startPoint = nil; endPoint = nil; routeCoordinates = []
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Legend").bold()
                    legendRow(color: SignalTier.good.color, label: "Good signal")
                    legendRow(color: SignalTier.poor.color, label: "Poor signal")
                    legendRow(color: SignalTier.dead.color, label: "Dead zone")
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).foregroundStyle(AppTheme.muted)
        }
    }

    private var userInfoPill: some View {
        VStack {
            if let loc = lastLocation {
                Text(String(
                    format: "Lat: %.4f, Lng: %.4f • Speed: %i µ",
                    loc.coordinate.latitude, loc.coordinate.longitude, 0 // zero is place holder gotta calc that
                ))
            } else {
                Text("Loading Stats...")
            }
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(AppTheme.muted)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
    }

    private func generateRoute() {
        guard let start = startPoint, let end = endPoint else { return }
        // Placeholder: straight line. Swap in MKDirections or your
        // low-signal-avoidance algorithm once that logic is defined.
        routeCoordinates = [start, end]
    }
    
    private func generateTestCircles() {
        let userCoord = UserStore.shared.coordinate

        circles = [
            SignalCircle(
                coordinate: CLLocationCoordinate2D(
                    latitude: userCoord.latitude + 0.002,
                    longitude: userCoord.longitude + 0.002
                ),
                radius: 150,
                tier: .good
            ),
            SignalCircle(
                coordinate: CLLocationCoordinate2D(
                    latitude: userCoord.latitude - 0.001,
                    longitude: userCoord.longitude + 0.003
                ),
                radius: 100,
                tier: .poor
            ),
            SignalCircle(
                coordinate: CLLocationCoordinate2D(
                    latitude: userCoord.latitude + 0.0015,
                    longitude: userCoord.longitude - 0.002
                ),
                radius: 80,
                tier: .dead
            )
        ]
    }
}

/*
#Preview {
    ContentView()
}
*/
