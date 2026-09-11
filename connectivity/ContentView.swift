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
    @State private var showLegend = false
    
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
            
            if showLegend { legendOverlay }
        }
        .onReceive(refreshTimer) { _ in
            if !hasCenteredOnFix && UserStore.shared.hasFix {
                hasCenteredOnFix = true
                loadCircles()
            }
            lastLocation = CLLocation(
                latitude: UserStore.shared.coordinate.latitude,
                longitude: UserStore.shared.coordinate.longitude
            )
        }
        .onAppear {
            UserStore.shared.requestPermissions()
            UserStore.shared.startUpdates()
            loadCircles()
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
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showLegend = true
                }
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 18))
            }
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
                    loc.coordinate.latitude,
                    loc.coordinate.longitude,
                    speedScore(
                        d: UserStore.shared.downloadMbps ?? 0,
                        u: UserStore.shared.uploadMbps ?? 0
                    )
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
    
    private func loadCircles() {
        // Replace with your actual endpoint
        guard let url = URL(string: "https://api.kalculator.lol/calculated?since=0") else { return }

        NetworkClient.shared.get(url: url, as: [SignalCircleJSON].self) { fetched, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to load circles: \(error)")
                    return
                }
                guard let fetched = fetched else {
                    return
                }
                circles = fetched.map { $0.toSignalCircle() }
            }
        }
    }
    
    private var legendOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                //.background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showLegend = false
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Scoring Guide").bold()
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showLegend = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                Text("Score blends download (70%) and upload (30%) speed on a logarithmic scale.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)

                VStack(alignment: .leading, spacing: 10) {
                    legendRow(color: colorForScore(100), label: "Excellent")
                    legendRow(color: colorForScore(75), label: "Good")
                    legendRow(color: colorForScore(50), label: "Fair")
                    legendRow(color: colorForScore(25), label: "Weak")
                    legendRow(color: colorForScore(0), label: "Dead zone")
                }
            }
            .padding(20)
            .frame(maxWidth: 300)
            .background(Color(red: 0.024, green: 0.055, blue: 0.078))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/*
#Preview {
    ContentView()
}
*/
