//
//  ContentView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//

import SwiftUI
import MapKit
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
    @State private var showSettings = false
    @State private var recenterMap: Bool = false
    
    @AppStorage("viewOnlyMode") private var viewOnlyMode: Bool = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = false
    
    @AppStorage("mapRefreshIntervalSeconds") private var mapRefreshIntervalSeconds: Int = 60
    @State private var mapRefreshCancellable: AnyCancellable?
    
    @AppStorage("speedTestIntervalSeconds") private var speedTestIntervalSeconds: Int = 5
    @State private var speedTestCancellable: AnyCancellable?
    

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 0) {
                        ConnectivityMapView(
                            startPoint: $startPoint,
                            endPoint: $endPoint,
                            circles: $circles,
                            routeCoordinates: routeCoordinates,
                            recenterMap: $recenterMap
                        )
                        .frame(height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(12)

                        sidebar
                            .padding(12)
                    }
                    .padding(.bottom, 90) // room for the pill
                }
            }

            userInfoPill

            if showLegend {
                legendOverlay
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
            restartSpeedTestTimer()
            restartMapRefreshTimer()
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .onChange(of: speedTestIntervalSeconds) { restartSpeedTestTimer() }
        .onChange(of: viewOnlyMode) { restartSpeedTestTimer() }
        .onChange(of: mapRefreshIntervalSeconds) { restartMapRefreshTimer() }
        .onChange(of: keepScreenAwake) { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0.016, green: 0.165, blue: 0.227))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(AppTheme.accent)
                        .font(.system(size: 12))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Connectivity").bold()
                Text("Find and avoid low-signal areas")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
            
            Spacer()
            Button {
                loadCircles()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 16))
            }
            Spacer().frame(width: 10)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showLegend = true
                }
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 16))
            }
            Spacer().frame(width: 10)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 16))
            }
            Spacer().frame(width: 10)
            Button {
                recenterMap = true
            } label: {
                Image(systemName: "location.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
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
        
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = true // get up to 3 routes to compare
        
        MKDirections(request: request).calculate { response, error in
            guard let routes = response?.routes, !routes.isEmpty else {
                print("Route error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            // Print all route scores so you can verify
            routes.enumerated().forEach { i, route in
                let score = self.scoreRoute(route)
                print("Route \(i): \(route.name) — signal score: \(String(format: "%.1f", score)) — ETA: \(Int(route.expectedTravelTime / 60))min")
            }
            
            let best = routes.max(by: { scoreRoute($0) < scoreRoute($1) })
            
            DispatchQueue.main.async {
                if let best = best {
                    print("Chose: \(best.name) as best signal route")
                    let pointCount = best.polyline.pointCount
                    var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
                    best.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
                    routeCoordinates = coords
                }
            }
        }
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

    private func restartSpeedTestTimer() {
        speedTestCancellable?.cancel()

        guard !viewOnlyMode else { return }

        speedTestCancellable = Timer.publish(every: Double(speedTestIntervalSeconds), on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                BackgroundTaskManager.shared.runSpeedTestAndLog()
        }
    }
    
    private func restartMapRefreshTimer() {
        mapRefreshCancellable?.cancel()
        mapRefreshCancellable = Timer.publish(every: Double(mapRefreshIntervalSeconds), on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                loadCircles()
        }
    }
    
    private func scoreRoute(_ route: MKRoute) -> Double {
        guard !circles.isEmpty else { return 0 }
        
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        
        // Sample every 5th point so we're not checking thousands
        let sampled = stride(from: 0, to: coords.count, by: 5).map { coords[$0] }
        
        var totalScore = 0.0
        var matched = 0
        
        for point in sampled {
            let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            
            // Find the closest circle to this point
            if let closest = circles.min(by: { a, b in
                let aLoc = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                let bLoc = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                return aLoc.distance(from: pointLocation) < bLoc.distance(from: pointLocation)
            })
            {
                let distance = CLLocation(
                    latitude: closest.coordinate.latitude,
                    longitude: closest.coordinate.longitude
                ).distance(from: pointLocation)
                
                // Only count it if the point is actually inside the circle
                if distance <= closest.radius {
                    totalScore += Double(closest.score)
                    matched += 1
                }
            }
        }
        
        // If no circles matched, return neutral score
        return matched > 0 ? totalScore / Double(matched) : 50.0
    }
}

/*
#Preview {
    ContentView()
}
*/
