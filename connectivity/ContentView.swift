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
    /// Kept here so a planned route survives closing and reopening the planner.
    @State private var routePlanner = RoutePlanner()
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
    @State private var isReportingOutage = false
    @State private var showOutageReportSheet = false
    @State private var outageReportLocation: CLLocationCoordinate2D?
    @State private var outageReports: [OutageReport] = []
    @State private var carrierFilterOptions: [String] = []
    @State private var activeCirclesRequestID = UUID()

    @Namespace private var glassNamespace

    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("hasRegisteredBefore") private var hasRegisteredBefore: Bool = false
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userCarrier") private var userCarrier: String = ""
    @AppStorage("mapCarrierFilter") private var carrierFilter: String = "All"
    
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
            // Assigning a new CLLocation re-renders the whole screen (map
            // included), so only do it when the user actually moved.
            if lastLocation == nil || updatedLocation.distance(from: lastLocation!) > 5 {
                lastLocation = updatedLocation
                updateAddressIfNeeded(for: updatedLocation)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .signalCircleCacheDidChange)) { notification in
            guard carrierFilter == "All" else { return }
            let entries = notification.object as? [SignalCircleJSON] ?? SignalCircleCache.loadEntries()
            circles = entries.map { $0.toSignalCircle() }
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
                startPoint: .constant(nil),
                endPoint: .constant(nil),
                circles: $circles,
                routeCoordinates: [],
                dataDisplayMode: signalDataDisplayMode,
                showsRouteBuilderOverlays: false,
                allowsRoutePointSelection: false,
                onMapTap: { coordinate in
                    guard isReportingOutage else { return }
                    outageReportLocation = coordinate
                    isReportingOutage = false
                    showOutageReportSheet = true
                },
                outageReports: outageReports,
                bottomChromeInset: 86,
                recenterMap: $recenterMap
            )
            .ignoresSafeArea()

            // Vignette so the floating glass chrome stays legible over any map tile.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Tap-anywhere-to-close layer for the chrome menu, below the chrome itself.
            if showHeaderMenu {
                Color.white.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            showHeaderMenu = false
                        }
                    }
            }

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                statusHUD
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .zIndex(1)

            if showLegend {
                legendOverlay
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showOutageReportSheet) {
            if let outageReportLocation {
                OutageReportSheet(location: outageReportLocation) {
                    loadOutageReports()
                }
                    .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(isPresented: $showRouteBuilderPage) {
            RouteBuilderView(
                planner: routePlanner,
                circles: $circles,
                dataDisplayMode: signalDataDisplayMode,
                onClose: { showRouteBuilderPage = false }
            )
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showLeaderboardPage) {
            LeaderboardView()
                .preferredColorScheme(.dark)
        }
        .foregroundStyle(.white)
    }

    /// Floating top chrome. Everything lives in one `GlassEffectContainer` so the
    /// separate glass capsules blend into each other as they come close.
    private var topChrome: some View {
        // spacing 0: the pills are independent controls and should not blend
        // into each other. The container is here for the menu's morph.
        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    routePillButton
                    Spacer(minLength: 6)
                    chromeCluster
                }

                HStack(spacing: 10) {
                    carrierFilterPill
                    Spacer(minLength: 0)
                }

                if showHeaderMenu {
                    headerMenuPanel
                        .glassEffectID("chromeMenu", in: glassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                        .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
                }

                if isReportingOutage {
                    outageTargetingBanner
                }
            }
        }
        .padding(.top, 4)
    }

    private var routePillButton: some View {
        Button {
            showRouteBuilderPage = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 13, weight: .bold))
                Text("Route")
                    .font(.ds(14, .bold))
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 16)
            .frame(height: 42)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .glassEffect(.regular.tint(AppTheme.accentDeep.opacity(0.20)).interactive(), in: Capsule())
        .accessibilityLabel("Open route planner")
    }

    /// Outage / account / menu grouped into a single glass capsule.
    private var chromeCluster: some View {
        HStack(spacing: 2) {
            clusterButton(
                systemName: "exclamationmark.triangle.fill",
                tint: isReportingOutage ? AppTheme.warn : AppTheme.accent
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isReportingOutage.toggle()
                    showHeaderMenu = false
                }
            }
            .accessibilityLabel("Report an outage")

            accountMenu

            clusterButton(
                systemName: showHeaderMenu ? "xmark" : "line.3.horizontal",
                tint: AppTheme.accent
            ) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    showHeaderMenu.toggle()
                }
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 4)
        .frame(height: 42)
        .glassEffect(.regular, in: Capsule())
    }

    private func clusterButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
    }

    private var accountMenu: some View {
        Menu {
            Section("Signed in") {
                Label(userName.isEmpty ? "Unknown account" : userName, systemImage: "person.fill")
                if !userCarrier.isEmpty {
                    Label(userCarrier, systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            Button {
                showSettings = true
            } label: {
                Label("Account settings", systemImage: "gearshape")
            }
            Button(role: .destructive) {
                logout()
            } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .accessibilityLabel("Account: \(userName)")
    }

    private var carrierFilterPill: some View {
        Menu {
            carrierMenuButton(title: "All carriers", value: "All")
            ForEach(carrierFilterOptions, id: \.self) { carrier in
                carrierMenuButton(title: carrier, value: carrier)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text(carrierFilter == "All" ? "All carriers" : carrierFilter)
                    .font(.ds(13, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("Carrier map layer: \(carrierFilter)")
        .onChange(of: carrierFilter) { _, _ in
            loadCircles()
        }
    }

    private var outageTargetingBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.warn)

            Text("Tap the map where the outage is")
                .font(.ds(13, .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isReportingOutage = false
                }
            } label: {
                Text("Cancel")
                    .font(.ds(13, .bold))
                    .foregroundStyle(AppTheme.warn)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(AppTheme.warn.opacity(0.20)), in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var headerMenuPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerMenuItem(title: "Refresh data", systemName: "arrow.clockwise") {
                loadCircles()
            }

            GlassDivider(inset: 48)

            headerMenuItem(title: "Recenter map", systemName: "location.fill") {
                recenterMap = true
            }

            GlassDivider(inset: 48)

            headerMenuItem(title: "Scoring guide", systemName: "info.circle") {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                    showLegend = true
                }
            }

            GlassDivider(inset: 48)

            headerMenuItem(title: "Leaderboard", systemName: "trophy.fill") {
                showLeaderboardPage = true
            }

            GlassDivider(inset: 48)

            headerMenuItem(title: "Settings", systemName: "gearshape.fill") {
                showSettings = true
            }

            GlassDivider(inset: 48)

            headerMenuItem(title: "Support", systemName: "questionmark.circle") {
                guard let url = URL(string: "https://api.kalculator.lol/support") else { return }
                UIApplication.shared.open(url)
            }
        }
        .padding(.vertical, 5)
        .frame(width: 232)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
    }

    @ViewBuilder
    private func carrierMenuButton(title: String, value: String) -> some View {
        Button {
            carrierFilter = value
        } label: {
            if carrierFilter == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func headerMenuItem(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                showHeaderMenu = false
            }
            action()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 22)

                Text(title)
                    .font(.ds(15, .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legendRow(color: Color, label: String, range: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .shadow(color: color.opacity(0.65), radius: 5)

            Text(label)
                .font(.ds(14, .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Text(range)
                .font(.dsMono(12, .medium))
                .foregroundStyle(AppTheme.muted)
        }
    }

    /// Bottom stack: quick map controls above the live telemetry dock.
    private var statusHUD: some View {
        VStack(alignment: .trailing, spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    GlassIconButton(systemName: "info", diameter: 44) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                            showLegend = true
                        }
                    }
                    .accessibilityLabel("Scoring guide")

                    GlassIconButton(systemName: "location.fill", diameter: 44) {
                        recenterMap = true
                    }
                    .accessibilityLabel("Recenter map")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: recenterMap) { _, new in new }

            TelemetryDock(
                isOnWiFi: isOnWiFi,
                fallbackScore: liveScore,
                addressLine: lastLocation == nil ? "Finding your location…" : currentAddress,
                carrier: userCarrier,
                viewOnlyMode: viewOnlyMode,
                nearby: nearbySummary,
                onRunTest: { BackgroundTaskManager.shared.runSpeedTestAndLog() }
            )
        }
    }

    /// Average of tested areas within 1.5 km of the user.
    private var nearbySummary: NearbySignalSummary? {
        guard let lastLocation, !circles.isEmpty else { return nil }
        let radius = 1_500.0
        let here = MKMapPoint(lastLocation.coordinate)
        let nearby = circles.filter { here.distance(to: MKMapPoint($0.coordinate)) <= radius }
        guard !nearby.isEmpty else { return nil }

        let average = nearby.map(\.score).reduce(0, +) / nearby.count
        return NearbySignalSummary(averageScore: average, spotCount: nearby.count, radiusMeters: radius)
    }

    private var isOnWiFi: Bool {
        NetworkStatusMonitor.shared.isUsingWiFi
    }

    private var liveScore: Int {
        speedScore(
            d: UserStore.shared.downloadMbps ?? 0,
            u: UserStore.shared.uploadMbps ?? 0
        )
    }

    private func loadCircles() {
        guard isLoggedIn else { return }

        loadOutageReports()

        let requestID = UUID()
        activeCirclesRequestID = requestID

        if carrierFilter != "All" {
            let selectedCarrier = carrierFilter
            guard let baseURL = URL(string: "https://api.kalculator.lol/calculated") else { return }
            let url = baseURL.appendingPathComponent(selectedCarrier)

            NetworkClient.shared.get(url: url, as: [SignalCircleJSON].self) { fetched, error in
                DispatchQueue.main.async {
                    guard activeCirclesRequestID == requestID else { return }
                    if let error {
                        print("Failed to load circles for \(selectedCarrier): \(error)")
                        return
                    }
                    guard let fetched else { return }
                    circles = fetched.map { $0.toSignalCircle() }
                }
            }
            return
        }

        let cachedEntries = SignalCircleCache.loadEntries()
        let since = SignalCircleCache.highestID(in: cachedEntries)

        if !cachedEntries.isEmpty {
            circles = cachedEntries.map { $0.toSignalCircle() }
        }

        guard let url = URL(string: "https://api.kalculator.lol/calculated?since=\(since)") else { return }

        NetworkClient.shared.get(url: url, as: [SignalCircleJSON].self) { fetched, error in
            DispatchQueue.main.async {
                guard activeCirclesRequestID == requestID else { return }
                if let error = error {
                    print("Failed to load circles: \(error)")
                    return
                }
                guard let fetched else {
                    return
                }

                guard !fetched.isEmpty else { return }
                let mergedEntries = SignalCircleCache.store(newEntries: fetched, existing: cachedEntries)
                circles = mergedEntries.map { $0.toSignalCircle() }
            }
        }
    }

    private func loadOutageReports() {
        guard let url = URL(string: "https://api.kalculator.lol/routes") else { return }

        NetworkClient.shared.get(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            as: [OutageReport].self
        ) { fetched, error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to load outage reports: \(error)")
                    return
                }
                guard let fetched else { return }
                outageReports = fetched
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
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        showLegend = false
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.accent)

                    Text("Scoring guide")
                        .font(.ds(19, .bold))

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            showLegend = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.muted)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.clear.interactive(), in: Circle())
                }

                Text("Every point blends download (70%) and upload (30%) speed on a logarithmic scale, so realistic speeds fill the range.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                SignalScaleBar()

                VStack(spacing: 11) {
                    legendRow(color: colorForScore(100), label: "Excellent", range: "85 – 100")
                    legendRow(color: colorForScore(75), label: "Good", range: "65 – 84")
                    legendRow(color: colorForScore(50), label: "Fair", range: "40 – 64")
                    legendRow(color: colorForScore(25), label: "Weak", range: "15 – 39")
                    legendRow(color: colorForScore(0), label: "Dead zone", range: "0 – 14")
                }
            }
            .padding(22)
            .frame(maxWidth: 330)
            .foregroundStyle(.white)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            .padding(24)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .zIndex(2)
    }

    private func startAuthenticatedServices() {
        UserStore.shared.requestPermissions()
        UserStore.shared.startUpdates()
        loadCarrierFilterOptions()
        loadCircles()
        restartSpeedTestTimer()
        restartMapRefreshTimer()
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    private func loadCarrierFilterOptions() {
        guard let url = URL(string: "https://api.kalculator.lol/populated-carriers") else { return }

        NetworkClient.shared.get(url: url, as: [String].self) { fetched, error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to load carrier filter options: \(error)")
                    return
                }
                guard let fetched else { return }
                carrierFilterOptions = fetched
                if carrierFilter != "All", !fetched.contains(carrierFilter) {
                    carrierFilter = "All"
                }
            }
        }
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
        UserDefaults.standard.removeObject(forKey: "userPassword")
        circles = []
        routePlanner.clear()
        lastLocation = nil
        currentAddress = "Finding address..."
        lastAddressLocation = nil
        isResolvingAddress = false
        hasCenteredOnFix = false
        LiveTelemetry.shared.reset()
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
    
}

private struct OutageReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var username: String = ""
    @AppStorage("userPassword") private var password: String = ""

    let location: CLLocationCoordinate2D
    let onReported: () -> Void

    @State private var message = ""
    @State private var locationAddress = "Looking up address…"
    @State private var isSubmitting = false
    @State private var showResultAlert = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var reportSucceeded = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        GlassCard(title: "Outage location", systemImage: "mappin.and.ellipse") {
                            HStack(spacing: 11) {
                                Image(systemName: "location.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(AppTheme.warn)

                                Text(locationAddress)
                                    .font(.ds(14, .medium))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                        }

                        GlassCard(title: "What is happening?", systemImage: "text.bubble.fill") {
                            VStack(alignment: .trailing, spacing: 8) {
                                TextField("Briefly describe the outage", text: $message, axis: .vertical)
                                    .lineLimit(3...5)
                                    .font(.ds(15, .medium))
                                    .foregroundStyle(.white)
                                    .tint(AppTheme.accent)
                                    .onChange(of: message) { _, updatedMessage in
                                        if updatedMessage.count > 100 {
                                            message = String(updatedMessage.prefix(100))
                                        }
                                    }

                                Text("\(message.count)/100")
                                    .font(.dsMono(11, .semibold))
                                    .foregroundStyle(message.count >= 100 ? AppTheme.warn : AppTheme.muted)
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                        }

                        Button {
                            submitReport()
                        } label: {
                            HStack(spacing: 9) {
                                if isSubmitting {
                                    ProgressView().tint(AppTheme.bgDeep)
                                    Text("Sending…")
                                } else {
                                    Image(systemName: "paperplane.fill")
                                    Text("Send report")
                                }
                            }
                            .font(.ds(16, .bold))
                            .foregroundStyle(AppTheme.bgDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(AppTheme.warn)
                        .disabled(!canSubmitReport)
                        .opacity(canSubmitReport ? 1 : 0.5)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Report outage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .alert(resultTitle, isPresented: $showResultAlert) {
                Button("OK", role: .cancel) {
                    if reportSucceeded { dismiss() }
                }
            } message: {
                Text(resultMessage)
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationBackground(.clear)
        .task {
            await lookupLocationAddress()
        }
    }

    private var canSubmitReport: Bool {
        !isSubmitting
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.isEmpty
            && !password.isEmpty
    }

    private func lookupLocationAddress() async {
        let tappedLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard let request = MKReverseGeocodingRequest(location: tappedLocation) else {
            locationAddress = "Address unavailable"
            return
        }

        let mapItems = try? await request.mapItems
        guard let mapItem = mapItems?.first else {
            locationAddress = "Address unavailable"
            return
        }

        let address = mapItem.address?.shortAddress
            ?? mapItem.address?.fullAddress
            ?? mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? mapItem.name
        if let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            locationAddress = address
        } else {
            locationAddress = "Address unavailable"
        }
    }

    private func submitReport() {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, trimmedMessage.count <= 100,
              !username.isEmpty, !password.isEmpty else { return }

        isSubmitting = true
        NetworkLogger.shared.reportOutage(
            username: username,
            password: password,
            latitude: location.latitude,
            longitude: location.longitude,
            message: trimmedMessage
        ) { error in
            DispatchQueue.main.async {
                isSubmitting = false
                reportSucceeded = error == nil
                resultTitle = error == nil ? "Report sent" : "Report not sent"
                resultMessage = error?.localizedDescription ?? "Thanks for reporting this outage."
                if error == nil {
                    onReported()
                }
                showResultAlert = true
            }
        }
    }
}

private struct AuthView: View {
    
    @State private var mode: AuthMode
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var carriers: [String] = []
    @State private var selectedCarrier = ""
    @State private var isLoadingCarriers = false
    @State private var carrierLoadError: String?
    @AppStorage("userCarrier") private var userCarrier: String = ""

    let onAuthenticated: (String, AuthMode) -> Void

    init(initialMode: AuthMode, onAuthenticated: @escaping (String, AuthMode) -> Void) {
        _mode = State(initialValue: initialMode)
        self.onAuthenticated = onAuthenticated
    }

    private var canSubmit: Bool {
        !isSubmitting && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && (mode != .register || !selectedCarrier.isEmpty)
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
            AuroraBackground()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        ZStack {
                            RadarPulse()
                                .frame(width: 170, height: 170)

                            Circle()
                                .fill(AppTheme.accentGradient)
                                .frame(width: 80, height: 80)
                                .blur(radius: 20)
                                .opacity(0.6)

                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 76, height: 76)
                                .glassEffect(.regular, in: Circle())
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        }
                        .frame(height: 130)

                        Text("Connectivity")
                            .font(.ds(29, .bold))
                            .foregroundStyle(.white)

                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 34)

                    VStack(spacing: 12) {
                        GlassField(systemImage: "person.fill") {
                            TextField("Username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .submitLabel(.next)
                        }

                        GlassField(systemImage: "lock.fill") {
                            SecureField("Password", text: $password)
                                .textContentType(mode == .register ? .newPassword : .password)
                                .submitLabel(.go)
                                .onSubmit(submit)
                        }

                        if mode == .register {
                            carrierSelector
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.bad)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submit) {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView().tint(AppTheme.bgDeep)
                                } else {
                                    Image(systemName: mode == .register ? "person.badge.plus" : "arrow.right")
                                    Text(title)
                                }
                            }
                            .font(.ds(16, .bold))
                            .foregroundStyle(AppTheme.bgDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(AppTheme.accent)
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                        .padding(.top, 4)

                        Button(switchPrompt) {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                mode = mode == .register ? .login : .register
                            }
                            errorMessage = nil
                            password = ""
                            if mode == .register {
                                Task { await loadCarriers() }
                            }
                        }
                        .font(.ds(13, .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    }

                    Text("Your readings help map dead zones for everyone.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task {
            if mode == .register {
                await loadCarriers()
            }
        }
    }

    private var carrierSelector: some View {
        VStack(alignment: .leading, spacing: 7) {
            Menu {
                ForEach(carriers, id: \.self) { carrier in
                    Button {
                        selectedCarrier = carrier
                    } label: {
                        if selectedCarrier == carrier {
                            Label(carrier, systemImage: "checkmark")
                        } else {
                            Text(carrier)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 22)

                    Text(carrierFieldLabel)
                        .font(.ds(15, .medium))
                        .foregroundStyle(selectedCarrier.isEmpty ? AppTheme.muted : .white)

                    Spacer(minLength: 8)

                    if isLoadingCarriers {
                        ProgressView().controlSize(.small).tint(AppTheme.accent)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .disabled(isLoadingCarriers || carriers.isEmpty)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            }

            if let carrierLoadError {
                HStack(spacing: 8) {
                    Text(carrierLoadError)
                        .font(.caption)
                        .foregroundStyle(AppTheme.bad)

                    Spacer(minLength: 0)

                    Button("Retry") {
                        Task { await loadCarriers() }
                    }
                    .font(.ds(12, .bold))
                    .foregroundStyle(AppTheme.accent)
                    .buttonStyle(.plain)
                    .disabled(isLoadingCarriers)
                }
            }
        }
    }

    private var carrierFieldLabel: String {
        if !selectedCarrier.isEmpty { return selectedCarrier }
        return isLoadingCarriers ? "Loading carriers…" : "Select a carrier"
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            errorMessage = "Enter a username and password."
            return
        }
        guard mode != .register || !selectedCarrier.isEmpty else {
            errorMessage = "Select a carrier to continue."
            return
        }

        isSubmitting = true
        errorMessage = nil
        let submittedPassword = password

        let completion: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                isSubmitting = false

                if error != nil {
                    errorMessage = mode == .register
                        ? "Registration failed. Try again."
                        : "Login failed. Check your username and password."
                    return
                }

                UserDefaults.standard.set(submittedPassword, forKey: "userPassword")
                if mode == .register {
                    userCarrier = selectedCarrier
                }
                password = ""
                onAuthenticated(trimmedUsername, mode)
            }
        }

        if mode == .register {
            NetworkLogger.shared.register(
                username: trimmedUsername,
                password: password,
                carrier: selectedCarrier,
                completion: completion
            )
        } else {
            NetworkLogger.shared.login(
                username: trimmedUsername, password: password, completion: completion)
        }
    }

    func loadCarriers() async {
        guard let url = URL(string: "https://api.kalculator.lol/carriers") else { return }

        isLoadingCarriers = true
        carrierLoadError = nil
        defer { isLoadingCarriers = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                carrierLoadError = "Could not load carriers. Try again."
                return
            }

            let serverCarriers = try JSONDecoder().decode([String].self, from: data)
            carriers = serverCarriers
            if !serverCarriers.contains(selectedCarrier) {
                selectedCarrier = ""
            }
            if serverCarriers.isEmpty {
                carrierLoadError = "No carriers are currently available."
            }
        } catch {
            print("Failed to load carriers:", error)
            carrierLoadError = "Could not load carriers. Check your connection and try again."
        }
    }
}

#Preview {
    ContentView()
}
