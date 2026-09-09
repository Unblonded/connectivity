//
//  ContentView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//

import SwiftUI
import CoreLocation

struct ContentView: View {
    @State private var samples: [ConnectivitySample] = []
    @State private var showSamples = true
    @State private var startPoint: CLLocationCoordinate2D?
    @State private var endPoint: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var lastLocation: CLLocation?
    
    private let refreshTimer = 0 //Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header

                    ConnectivityMapView(
                        samples: $samples,
                        startPoint: $startPoint,
                        endPoint: $endPoint,
                        showSamples: showSamples,
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
        //.onReceive(refreshTimer) { _ in
            //lastLocation = LocationManager.shared.lastLocation
        //}
        .onAppear {
            //LocationManager.shared.requestPermissions()
            //LocationManager.shared.startUpdates()
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
                    Button("Clear") {
                        startPoint = nil; endPoint = nil; routeCoordinates = []
                    }
                    Button("Generate Route") { generateRoute() }
                        .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Legend").bold()
                    legendRow(color: SignalTier.good.color, label: "Good signal")
                    legendRow(color: SignalTier.poor.color, label: "Poor signal")
                    legendRow(color: SignalTier.dead.color, label: "Dead zone")
                }
                .padding(.top, 8)
            }

            Toggle("Show sample points", isOn: $showSamples)

            VStack(alignment: .leading, spacing: 8) {
                Text("Manage Samples").font(.headline)
                SampleFormView(samples: $samples)
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
                    format: "Lat: %.4f, Lng: %.4f • Speed: %.1f m/s",
                    loc.coordinate.latitude, loc.coordinate.longitude, max(loc.speed, 0)
                ))
            } else {
                Text("Lat: --, Lng: -- • Speed: --")
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
}

#Preview {
    ContentView()
}
