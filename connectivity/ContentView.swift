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

enum AuthMode: Equatable {
    case login
    case register
}

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
    
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("hasRegisteredBefore") private var hasRegisteredBefore: Bool = false
    @AppStorage("userName") private var userName: String = ""
    
    @AppStorage("viewOnlyMode") private var viewOnlyMode: Bool = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = false
    
    @AppStorage("mapRefreshIntervalSeconds") private var mapRefreshIntervalSeconds: Int = 60
    @State private var mapRefreshCancellable: AnyCancellable?
    
    @AppStorage("speedTestIntervalSeconds") private var speedTestIntervalSeconds: Int = 5
    @State private var speedTestCancellable: AnyCancellable?
    

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if isLoggedIn {
                mainContent
            } else {
                AuthView(initialMode: hasRegisteredBefore ? .login : .register) { username, mode in
                    userName = username
                    hasRegisteredBefore = true
                    isLoggedIn = true
                }
            }
        }
        .onReceive(refreshTimer) { _ in
            guard isLoggedIn else { return }

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
            guard isLoggedIn else { return }
            startAuthenticatedServices()
        }
        .onChange(of: isLoggedIn) {
            if isLoggedIn {
                startAuthenticatedServices()
            } else {
                stopAuthenticatedServices()
            }
        }
        .onChange(of: speedTestIntervalSeconds) { restartSpeedTestTimer() }
        .onChange(of: viewOnlyMode) { restartSpeedTestTimer() }
        .onChange(of: mapRefreshIntervalSeconds) { restartMapRefreshTimer() }
        .onChange(of: keepScreenAwake) { UIApplication.shared.isIdleTimerDisabled = isLoggedIn && keepScreenAwake }
        .preferredColorScheme(.dark)
    }

    private var mainContent: some View {
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
                .preferredColorScheme(.dark)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(red: 0.016, green: 0.165, blue: 0.227))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(AppTheme.accent)
                        .font(.system(size: 12))
                )
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connectivity")
                    .font(.headline)
                    .lineLimit(1)
                Text(userName.isEmpty ? "Find and avoid low-signal areas" : "Signed in as \(userName)")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.top, 1)
            
            Spacer(minLength: 8)

            HStack(spacing: 14) {
                headerButton(systemName: "location.fill") {
                    recenterMap = true
                }

                headerButton(systemName: "arrow.clockwise") {
                    loadCircles()
                }

                headerButton(systemName: "info.circle") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showLegend = true
                    }
                }

                headerButton(systemName: "gearshape") {
                    showSettings = true
                }

                Divider()
                    .frame(height: 18)
                    .overlay(AppTheme.muted.opacity(0.4))

                headerButton(systemName: "rectangle.portrait.and.arrow.right") {
                    logout()
                }
            }
            .padding(.top, 5)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(red: 0.024, green: 0.055, blue: 0.078).opacity(0.98))
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(AppTheme.accent)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
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
        .foregroundStyle(.white)
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
        guard isLoggedIn else { return }

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
            .foregroundStyle(.white)
            .background(Color(red: 0.024, green: 0.055, blue: 0.078))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func startAuthenticatedServices() {
        UserStore.shared.requestPermissions()
        UserStore.shared.startUpdates()
        loadCircles()
        restartSpeedTestTimer()
        restartMapRefreshTimer()
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    private func stopAuthenticatedServices() {
        speedTestCancellable?.cancel()
        mapRefreshCancellable?.cancel()
        speedTestCancellable = nil
        mapRefreshCancellable = nil
        UIApplication.shared.isIdleTimerDisabled = false
        UserStore.shared.stopUpdates()
    }

    private func logout() {
        isLoggedIn = false
        userName = ""
        circles = []
        startPoint = nil
        endPoint = nil
        routeCoordinates = []
        lastLocation = nil
        hasCenteredOnFix = false
        showLegend = false
        showSettings = false
    }

    private func restartSpeedTestTimer() {
        speedTestCancellable?.cancel()

        guard isLoggedIn, !viewOnlyMode else { return }

        speedTestCancellable = Timer.publish(every: Double(speedTestIntervalSeconds), on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard isLoggedIn else { return }
                BackgroundTaskManager.shared.runSpeedTestAndLog()
        }
    }
    
    private func restartMapRefreshTimer() {
        mapRefreshCancellable?.cancel()

        guard isLoggedIn else { return }

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

private struct AuthView: View {
    @State private var mode: AuthMode
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    let onAuthenticated: (String, AuthMode) -> Void

    init(initialMode: AuthMode, onAuthenticated: @escaping (String, AuthMode) -> Void) {
        _mode = State(initialValue: initialMode)
        self.onAuthenticated = onAuthenticated
    }

    private var canSubmit: Bool {
        !isSubmitting && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var title: String {
        mode == .register ? "Create Account" : "Log In"
    }

    private var subtitle: String {
        mode == .register
            ? "Register before starting location, map, and speed logging services."
            : "Log in to start location, map, and speed logging services."
    }

    private var switchPrompt: String {
        mode == .register ? "Already have an account? Log in" : "Need an account? Register"
    }

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Circle()
                        .fill(Color(red: 0.016, green: 0.165, blue: 0.227))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(AppTheme.accent)
                                .font(.system(size: 26))
                        )

                    Text("Connectivity")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.next)
                        .foregroundStyle(.white)
                        .tint(AppTheme.accent)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    SecureField("Password", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .foregroundStyle(.white)
                        .tint(AppTheme.accent)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(title)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)

                    Button(switchPrompt) {
                        mode = mode == .register ? .login : .register
                        errorMessage = nil
                        password = ""
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 4)
                }
                .foregroundStyle(.white)
            }
            .padding(24)
            .frame(maxWidth: 360)
        }
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            errorMessage = "Enter a username and password."
            return
        }

        isSubmitting = true
        errorMessage = nil

        let completion: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                isSubmitting = false

                if error != nil {
                    errorMessage = mode == .register
                        ? "Registration failed. Try again."
                        : "Login failed. Check your username and password."
                    return
                }

                password = ""
                onAuthenticated(trimmedUsername, mode)
            }
        }

        if mode == .register {
            NetworkLogger.shared.register(username: trimmedUsername, password: password, completion: completion)
        } else {
            NetworkLogger.shared.login(username: trimmedUsername, password: password, completion: completion)
        }
    }
}

#Preview {
    ContentView()
}


