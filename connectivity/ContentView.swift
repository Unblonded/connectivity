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

enum RouteStartMode: String, CaseIterable, Identifiable {
    case currentLocation
    case customAddress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .currentLocation: return "Current Location"
        case .customAddress: return "Address"
        }
    }
}

private enum RouteBuilderError: LocalizedError {
    case currentLocationUnavailable
    case emptyAddress(String)
    case locationNotFound(String)
    case noRoutesFound

    var errorDescription: String? {
        switch self {
        case .currentLocationUnavailable:
            return "Current location is not ready yet. Try again in a moment or enter a start address."
        case .emptyAddress(let field):
            return "Enter a \(field) address."
        case .locationNotFound(let query):
            return "Could not find \"\(query)\". Try a more specific address."
        case .noRoutesFound:
            return "No driving routes were found for those locations."
        }
    }
}

struct ContentView: View {
    @State private var circles: [SignalCircle] = []
    @State private var startPoint: CLLocationCoordinate2D?
    @State private var endPoint: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeStartMode: RouteStartMode = .currentLocation
    @State private var routeStartAddress = ""
    @State private var routeDestinationAddress = ""
    @State private var routeErrorMessage: String?
    @State private var isResolvingRoute = false
    @State private var lastLocation: CLLocation?
    @State private var currentAddress = "Finding address..."
    @State private var lastAddressLocation: CLLocation?
    @State private var isResolvingAddress = false
    @State private var hasCenteredOnFix = false
    @State private var showLegend = false
    @State private var showSettings = false
    @State private var showRouteBuilderPage = false
    @State private var showLeaderboardPage = false
    @State private var showHeaderMenu = false
    @State private var recenterMap: Bool = false
    
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("hasRegisteredBefore") private var hasRegisteredBefore: Bool = false
    @AppStorage("userName") private var userName: String = ""
    
    @AppStorage("viewOnlyMode") private var viewOnlyMode: Bool = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = false
    @AppStorage("signalDataDisplayMode") private var signalDataDisplayModeRaw: String = SignalDataDisplayMode.numbersAndCircles.rawValue
    
    @AppStorage("mapRefreshIntervalSeconds") private var mapRefreshIntervalSeconds: Int = 60
    @State private var mapRefreshCancellable: AnyCancellable?
    
    @AppStorage("speedTestIntervalSeconds") private var speedTestIntervalSeconds: Int = 5
    @State private var speedTestCancellable: AnyCancellable?
    

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var signalDataDisplayMode: SignalDataDisplayMode {
        SignalDataDisplayMode(rawValue: signalDataDisplayModeRaw) ?? .numbersAndCircles
    }

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
            let updatedLocation = CLLocation(
                latitude: UserStore.shared.coordinate.latitude,
                longitude: UserStore.shared.coordinate.longitude
            )
            lastLocation = updatedLocation
            updateAddressIfNeeded(for: updatedLocation)
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
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            ConnectivityMapView(
                startPoint: $startPoint,
                endPoint: $endPoint,
                circles: $circles,
                routeCoordinates: [],
                dataDisplayMode: signalDataDisplayMode,
                showsRouteBuilderOverlays: false,
                allowsRoutePointSelection: false,
                recenterMap: $recenterMap
            )
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                header
                Spacer()
            }

            if showHeaderMenu {
                headerMenuOverlay
            }

            VStack {
                Spacer()
                userInfoPill
            }

            if showLegend {
                legendOverlay
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showRouteBuilderPage) {
            routeBuilderPage
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showLeaderboardPage) {
            LeaderboardView()
                .preferredColorScheme(.dark)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                showRouteBuilderPage = true
            } label: {
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
                        Text(userName.isEmpty ? "Find and avoid low-signal areas" : "Open route builder")
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.top, 1)
                }
            }
            .buttonStyle(.plain)
            
            Spacer(minLength: 8)

            HStack(spacing: 14) {
                headerButton(systemName: "line.3.horizontal") {
                    showHeaderMenu.toggle()
                }

                headerButton(systemName: "location.fill") {
                    recenterMap = true
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
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var headerMenuOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerMenuItem(title: "Refresh", systemName: "arrow.clockwise") {
                loadCircles()
            }

            headerMenuItem(title: "Info", systemName: "info.circle") {
                withAnimation(.easeOut(duration: 0.2)) {
                    showLegend = true
                }
            }

            headerMenuItem(title: "Leaderboard", systemName: "trophy") {
                showLeaderboardPage = true
            }

            headerMenuItem(title: "Settings", systemName: "gearshape") {
                showSettings = true
            }
        }
        .padding(.vertical, 8)
        .frame(width: 190)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        .padding(.top, 56)
        .padding(.trailing, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .zIndex(1)
    }

    private func headerMenuItem(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            showHeaderMenu = false
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
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

    private var routeBuilderPage: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            ConnectivityMapView(
                startPoint: $startPoint,
                endPoint: $endPoint,
                circles: $circles,
                routeCoordinates: routeCoordinates,
                dataDisplayMode: signalDataDisplayMode,
                showsRouteBuilderOverlays: true,
                allowsRoutePointSelection: false,
                recenterMap: $recenterMap
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                routeBuilderHeader
                Spacer()
                routeBuilderControls
            }
        }
        .foregroundStyle(.white)
    }

    private var routeBuilderHeader: some View {
        HStack(spacing: 12) {
            Button {
                showRouteBuilderPage = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Route Builder")
                    .font(.headline)
                Text("Search an address, place, or route from your location.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            headerButton(systemName: "location.fill") {
                recenterMap = true
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var routeBuilderControls: some View {
        VStack(spacing: 12) {
            Picker("Start", selection: $routeStartMode) {
                ForEach(RouteStartMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if routeStartMode == .customAddress {
                routeTextField(title: "Start", placeholder: "Start address or place", text: $routeStartAddress)
            }

            routeTextField(title: "Destination", placeholder: "Destination address or place", text: $routeDestinationAddress)

            if let routeErrorMessage {
                Text(routeErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    generateRoute()
                } label: {
                    if isResolvingRoute {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerateRoute)

                Button {
                    clearRouteBuilder()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                routePointRow(title: "Start", coordinate: startPoint, symbol: "1.circle.fill")
                routePointRow(title: "End", coordinate: endPoint, symbol: "2.circle.fill")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var canGenerateRoute: Bool {
        guard !isResolvingRoute else { return false }
        guard !routeDestinationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if routeStartMode == .customAddress {
            return !routeStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    private func routeTextField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.route)
                .onSubmit(generateRoute)
                .foregroundStyle(.white)
                .tint(AppTheme.accent)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func routePointRow(title: String, coordinate: CLLocationCoordinate2D?, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(coordinate == nil ? AppTheme.muted : AppTheme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                if let coordinate {
                    Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.muted)
                } else {
                    Text("Not set")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).foregroundStyle(AppTheme.muted)
        }
    }

    private var userInfoPill: some View {
        VStack {
            if lastLocation != nil {
                userInfoText
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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

    private var userInfoText: Text {
        if NetworkStatusMonitor.shared.isUsingWiFi {
            return Text("Speed: \(Image(systemName: "wifi")) • \(currentAddress)")
        }

        return Text("\(speedSummary) \(Image(systemName: "cellularbars")) • \(currentAddress)")
    }

    private var speedSummary: String {
        let score = speedScore(
            d: UserStore.shared.downloadMbps ?? 0,
            u: UserStore.shared.uploadMbps ?? 0
        )
        return "Speed: \(score)"
    }

    private func generateRoute() {
        guard canGenerateRoute else { return }

        let destinationQuery = routeDestinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let startQuery = routeStartAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchCenter = UserStore.shared.coordinate

        isResolvingRoute = true
        routeErrorMessage = nil
        routeCoordinates = []

        switch routeStartMode {
        case .currentLocation:
            guard UserStore.shared.hasFix else {
                finishRouteGeneration(with: RouteBuilderError.currentLocationUnavailable)
                return
            }
            resolveDestinationAndCalculateRoute(destinationQuery: destinationQuery, start: searchCenter)
        case .customAddress:
            resolveRouteCoordinate(for: startQuery, near: searchCenter, emptyFieldName: "start") { result in
                switch result {
                case .success(let start):
                    resolveDestinationAndCalculateRoute(destinationQuery: destinationQuery, start: start)
                case .failure(let error):
                    finishRouteGeneration(with: error)
                }
            }
        }
    }

    private func resolveDestinationAndCalculateRoute(destinationQuery: String, start: CLLocationCoordinate2D) {
        resolveRouteCoordinate(for: destinationQuery, near: start, emptyFieldName: "destination") { result in
            switch result {
            case .success(let end):
                DispatchQueue.main.async {
                    startPoint = start
                    endPoint = end
                }
                calculateRoute(from: start, to: end)
            case .failure(let error):
                finishRouteGeneration(with: error)
            }
        }
    }

    private func resolveRouteCoordinate(
        for query: String,
        near coordinate: CLLocationCoordinate2D,
        emptyFieldName: String,
        completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            completion(.failure(RouteBuilderError.emptyAddress(emptyFieldName)))
            return
        }

        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        let request = MKLocalSearch.Request(naturalLanguageQuery: trimmedQuery, region: region)
        request.resultTypes = [.address, .pointOfInterest]

        MKLocalSearch(request: request).start { response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let mapItem = response?.mapItems.first else {
                completion(.failure(RouteBuilderError.locationNotFound(trimmedQuery)))
                return
            }

            completion(.success(mapItem.location.coordinate))
        }
    }

    private func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        MKDirections(request: request).calculate { response, error in
            guard let routes = response?.routes, !routes.isEmpty else {
                print("Route error: \(error?.localizedDescription ?? "unknown")")
                finishRouteGeneration(with: RouteBuilderError.noRoutesFound)
                return
            }

            routes.enumerated().forEach { index, route in
                let score = scoreRoute(route)
                print("Route \(index): \(route.name) — signal score: \(String(format: "%.1f", score)) — ETA: \(Int(route.expectedTravelTime / 60))min")
            }

            guard let best = routes.max(by: { scoreRoute($0) < scoreRoute($1) }) else {
                finishRouteGeneration(with: RouteBuilderError.noRoutesFound)
                return
            }

            print("Chose: \(best.name) as best signal route")
            let pointCount = best.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
            best.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

            DispatchQueue.main.async {
                routeCoordinates = coords
                isResolvingRoute = false
            }
        }
    }

    private func finishRouteGeneration(with error: Error) {
        DispatchQueue.main.async {
            routeErrorMessage = error.localizedDescription
            isResolvingRoute = false
        }
    }

    private func clearRouteBuilder() {
        startPoint = nil
        endPoint = nil
        routeCoordinates = []
        routeStartAddress = ""
        routeDestinationAddress = ""
        routeErrorMessage = nil
        isResolvingRoute = false
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

    private func updateAddressIfNeeded(for location: CLLocation) {
        guard !isResolvingAddress else { return }

        if let lastAddressLocation,
           location.distance(from: lastAddressLocation) < 50 {
            return
        }

        guard let request = MKReverseGeocodingRequest(location: location) else {
            currentAddress = "Address unavailable"
            return
        }

        isResolvingAddress = true

        Task {
            let mapItems = try? await request.mapItems

            await MainActor.run {
                isResolvingAddress = false

                guard let mapItem = mapItems?.first else {
                    currentAddress = "Address unavailable"
                    return
                }

                currentAddress = formattedAddress(from: mapItem)
                lastAddressLocation = location
            }
        }
    }

    private func formattedAddress(from mapItem: MKMapItem) -> String {
        if let shortAddress = mapItem.address?.shortAddress, !shortAddress.isEmpty {
            return streetOnlyAddress(from: shortAddress)
        }

        if let fullAddress = mapItem.address?.fullAddress, !fullAddress.isEmpty {
            return streetOnlyAddress(from: fullAddress)
        }

        if let displayAddress = mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true),
           !displayAddress.isEmpty {
            return streetOnlyAddress(from: displayAddress)
        }

        return mapItem.name ?? "Address unavailable"
    }

    private func streetOnlyAddress(from address: String) -> String {
        let firstLine = address
            .components(separatedBy: .newlines)
            .first?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstLine, !firstLine.isEmpty else {
            return "Address unavailable"
        }

        return firstLine
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
        routeStartMode = .currentLocation
        routeStartAddress = ""
        routeDestinationAddress = ""
        routeErrorMessage = nil
        isResolvingRoute = false
        lastLocation = nil
        currentAddress = "Finding address..."
        lastAddressLocation = nil
        isResolvingAddress = false
        hasCenteredOnFix = false
        showLegend = false
        showSettings = false
        showRouteBuilderPage = false
        showLeaderboardPage = false
        showHeaderMenu = false
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
