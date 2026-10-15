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

private struct SignalRouteOption {
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let signalScore: Double
    let travelTime: TimeInterval
    let usesDataWaypoint: Bool

    var selectionScore: Double {
        signalScore - (travelTime / 300.0)
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
    @State private var routeSummary: String?
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
            lastLocation = updatedLocation
            updateAddressIfNeeded(for: updatedLocation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .signalCircleCacheDidChange)) { _ in
            if carrierFilter == "All" {
                circles = SignalCircleCache.loadEntries().map { $0.toSignalCircle() }
            }
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
            routeBuilderPage
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
                LinearGradient(
                    colors: [Color.black.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                routeBuilderHeader
                    .padding(.horizontal, 14)

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                routeBuilderControls
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .foregroundStyle(.white)
    }

    private var routeBuilderHeader: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    showRouteBuilderPage = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .glassEffect(.regular.interactive(), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("ROUTE PLANNER")
                        .font(.ds(9, .bold))
                        .tracking(1.3)
                        .foregroundStyle(AppTheme.muted)

                    Text("Plan your drive")
                        .font(.ds(16, .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 15)
                .frame(height: 42)
                .glassEffect(.regular, in: Capsule())

                Spacer(minLength: 0)

                Button {
                    recenterMap = true
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .glassEffect(.regular.interactive(), in: Circle())
            }
        }
        .padding(.top, 4)
    }

    private var routeBuilderControls: some View {
        VStack(alignment: .leading, spacing: 15) {
            Capsule()
                .fill(Color.white.opacity(0.26))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Build a route")
                        .font(.ds(21, .bold))

                    Text("Find a path with better signal")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                if routeStartPointExists || !routeDestinationAddress.isEmpty || !routeCoordinates.isEmpty {
                    Button("Clear") { clearRouteBuilder() }
                        .font(.ds(14, .bold))
                        .foregroundStyle(AppTheme.accent)
                        .buttonStyle(.plain)
                }
            }

            GlassSegmented(
                options: [
                    (label: "My location", value: RouteStartMode.currentLocation),
                    (label: "Address", value: RouteStartMode.customAddress)
                ],
                selection: $routeStartMode
            )

            VStack(spacing: 9) {
                if routeStartMode == .currentLocation {
                    GlassField(systemImage: "location.fill", tint: AppTheme.good) {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("START")
                                    .font(.ds(9, .bold))
                                    .tracking(0.9)
                                    .foregroundStyle(AppTheme.muted)

                                Text("Current location")
                                    .font(.ds(15, .medium))
                                    .foregroundStyle(.white)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                } else {
                    GlassField(systemImage: "circle.circle.fill", tint: AppTheme.good) {
                        TextField("Starting point", text: $routeStartAddress)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(false)
                            .submitLabel(.next)
                    }
                }

                GlassField(systemImage: "mappin.and.ellipse", tint: .orange) {
                    TextField("Where to?", text: $routeDestinationAddress)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.route)
                        .onSubmit(generateRoute)
                }
            }

            if let routeErrorMessage {
                Label(routeErrorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.bad)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let routeSummary, canStartGuidance {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.good)

                    Text(routeSummary)
                        .font(.ds(14, .semibold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassEffect(.clear.tint(AppTheme.good.opacity(0.18)), in: Capsule())
            }

            Button {
                generateRoute()
            } label: {
                HStack(spacing: 9) {
                    if isResolvingRoute {
                        ProgressView().tint(AppTheme.bgDeep)
                        Text("Finding best route…")
                    } else {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        Text(routeSummary == nil ? "Find best route" : "Recalculate route")
                    }
                }
                .font(.ds(16, .bold))
                .foregroundStyle(AppTheme.bgDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.accent)
            .disabled(!canGenerateRoute)
            .opacity(canGenerateRoute ? 1 : 0.5)

            if canStartGuidance {
                Button {
                    startGuidance()
                } label: {
                    Label("Start navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.ds(15, .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        // Extra bottom padding clears the home indicator, since the sheet's
        // glass is extended past the safe area to meet the screen edge.
        .padding(.bottom, 42)
        .glassEffect(
            .regular,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
            .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 26, y: -10)
    }

    private var routeStartPointExists: Bool {
        startPoint != nil || !routeStartAddress.isEmpty
    }

    private var canGenerateRoute: Bool {
        guard !isResolvingRoute else { return false }
        guard !routeDestinationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if routeStartMode == .customAddress {
            return !routeStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    private var canStartGuidance: Bool {
        startPoint != nil && endPoint != nil && routeCoordinates.count > 1 && !isResolvingRoute
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

    /// Bottom readout: live score gauge, resolved street address and link type.
    private var statusHUD: some View {
        HStack(spacing: 12) {
            if isOnWiFi {
                Image(systemName: "wifi")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.14), in: Circle())
                    .overlay {
                        Circle().strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1)
                    }
            } else {
                ScoreRing(score: liveScore, diameter: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isOnWiFi ? "Wi-Fi connected" : scoreDescriptor(liveScore))
                    .font(.ds(14, .bold))
                    .foregroundStyle(.white)

                Text(lastLocation == nil ? "Finding your location…" : currentAddress)
                    .font(.dsMono(11, .medium))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                if !userCarrier.isEmpty {
                    Text(userCarrier)
                        .font(.ds(11, .bold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                } else if !isOnWiFi {
                    Image(systemName: "cellularbars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                if viewOnlyMode {
                    Text("VIEW ONLY")
                        .font(.ds(8, .bold))
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .overlay {
            Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
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

    private func generateRoute() {
        guard canGenerateRoute else { return }

        let destinationQuery = routeDestinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let startQuery = routeStartAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchCenter = UserStore.shared.coordinate

        isResolvingRoute = true
        routeErrorMessage = nil
        routeSummary = nil
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
        let waypoints = signalWaypointCandidates(from: start, to: end)
        let group = DispatchGroup()
        let lock = NSLock()
        var options: [SignalRouteOption] = []

        func appendOptions(_ newOptions: [SignalRouteOption]) {
            lock.lock()
            options.append(contentsOf: newOptions)
            lock.unlock()
        }

        group.enter()
        calculateRouteOptions(from: start, to: end, via: nil) { routeOptions in
            appendOptions(routeOptions)
            group.leave()
        }

        for waypoint in waypoints {
            group.enter()
            calculateRouteOptions(from: start, to: end, via: waypoint.coordinate) { routeOptions in
                appendOptions(routeOptions)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard let best = options.max(by: { $0.selectionScore < $1.selectionScore }) else {
                finishRouteGeneration(with: RouteBuilderError.noRoutesFound)
                return
            }

            print("Chose: \(best.name) — signal score: \(String(format: "%.1f", best.signalScore)) — ETA: \(Int(best.travelTime / 60))min — data waypoint: \(best.usesDataWaypoint)")
            routeCoordinates = best.coordinates
            routeSummary = "\(Int(best.travelTime / 60)) min · Signal score \(Int(best.signalScore.rounded()))"
            isResolvingRoute = false
        }
    }

    private func calculateRouteOptions(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        via waypoint: CLLocationCoordinate2D?,
        completion: @escaping ([SignalRouteOption]) -> Void
    ) {
        if let waypoint {
            calculateRouteLeg(from: start, to: waypoint, requestsAlternateRoutes: false) { firstLegs in
                guard let firstLeg = firstLegs.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                    completion([])
                    return
                }

                calculateRouteLeg(from: waypoint, to: end, requestsAlternateRoutes: false) { secondLegs in
                    guard let secondLeg = secondLegs.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                        completion([])
                        return
                    }

                    let coordinates = combinedCoordinates(for: [firstLeg, secondLeg])
                    let travelTime = firstLeg.expectedTravelTime + secondLeg.expectedTravelTime
                    let signalScore = scoreRouteCoordinates(coordinates)
                    completion([
                        SignalRouteOption(
                            name: "Via signal data",
                            coordinates: coordinates,
                            signalScore: signalScore,
                            travelTime: travelTime,
                            usesDataWaypoint: true
                        )
                    ])
                }
            }
            return
        }

        calculateRouteLeg(from: start, to: end, requestsAlternateRoutes: true) { routes in
            let routeOptions = routes.map { route in
                let coordinates = coordinates(for: route)
                return SignalRouteOption(
                    name: route.name.isEmpty ? "Direct route" : route.name,
                    coordinates: coordinates,
                    signalScore: scoreRouteCoordinates(coordinates),
                    travelTime: route.expectedTravelTime,
                    usesDataWaypoint: false
                )
            }
            completion(routeOptions)
        }
    }

    private func calculateRouteLeg(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        requestsAlternateRoutes: Bool,
        completion: @escaping ([MKRoute]) -> Void
    ) {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = requestsAlternateRoutes

        MKDirections(request: request).calculate { response, error in
            if let error {
                print("Route leg error: \(error.localizedDescription)")
            }
            completion(response?.routes ?? [])
        }
    }

    private func coordinates(for route: MKRoute) -> [CLLocationCoordinate2D] {
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }

    private func combinedCoordinates(for routes: [MKRoute]) -> [CLLocationCoordinate2D] {
        routes.enumerated().flatMap { index, route in
            let coords = coordinates(for: route)
            return index == 0 ? coords : Array(coords.dropFirst())
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
        routeSummary = nil
        routeStartAddress = ""
        routeDestinationAddress = ""
        routeErrorMessage = nil
        isResolvingRoute = false
    }

    private func startGuidance() {
        guard let startPoint, let endPoint else { return }

        let destination = MKMapItem(location: CLLocation(latitude: endPoint.latitude, longitude: endPoint.longitude), address: nil)
        destination.name = routeDestinationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Destination"
            : routeDestinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let source: MKMapItem
        if routeStartMode == .currentLocation {
            source = MKMapItem.forCurrentLocation()
        } else {
            source = MKMapItem(location: CLLocation(latitude: startPoint.latitude, longitude: startPoint.longitude), address: nil)
            let startName = routeStartAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            source.name = startName.isEmpty ? "Start" : startName
        }

        MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
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

                let mergedEntries = SignalCircleCache.store(newEntries: fetched)
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
    
    private func signalWaypointCandidates(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> [SignalCircle] {
        guard !circles.isEmpty else { return [] }

        let startPoint = MKMapPoint(start)
        let endPoint = MKMapPoint(end)
        let directDistance = max(startPoint.distance(to: endPoint), 1)
        let corridorWidth = min(max(directDistance * 0.25, 750), 5_000)
        let maxAddedDistance = max(directDistance * 0.75, 2_000)

        let rankedCandidates = circles
            .filter { $0.score >= 55 }
            .compactMap { circle -> (circle: SignalCircle, rank: Double)? in
                let point = MKMapPoint(circle.coordinate)
                let progress = routeProgress(for: point, from: startPoint, to: endPoint)
                guard (0.08...0.92).contains(progress) else { return nil }

                let distanceFromRoute = distanceFromSegment(point, start: startPoint, end: endPoint)
                guard distanceFromRoute <= corridorWidth else { return nil }

                let addedDistance = startPoint.distance(to: point) + point.distance(to: endPoint) - directDistance
                guard addedDistance <= maxAddedDistance else { return nil }

                let rank = Double(circle.score) * 4.0 - (distanceFromRoute / 120.0) - (addedDistance / 250.0)
                return (circle, rank)
            }
            .sorted { $0.rank > $1.rank }

        var selected: [SignalCircle] = []
        for candidate in rankedCandidates {
            let candidatePoint = MKMapPoint(candidate.circle.coordinate)
            let isTooClose = selected.contains { existing in
                MKMapPoint(existing.coordinate).distance(to: candidatePoint) < 600
            }

            if !isTooClose {
                selected.append(candidate.circle)
            }

            if selected.count == 6 {
                break
            }
        }

        return selected
    }

    private func routeProgress(for point: MKMapPoint, from start: MKMapPoint, to end: MKMapPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }

        let progress = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        return min(max(progress, 0), 1)
    }

    private func distanceFromSegment(_ point: MKMapPoint, start: MKMapPoint, end: MKMapPoint) -> CLLocationDistance {
        let progress = routeProgress(for: point, from: start, to: end)
        let projected = MKMapPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
        return point.distance(to: projected)
    }

    private func scoreRoute(_ route: MKRoute) -> Double {
        scoreRouteCoordinates(coordinates(for: route))
    }

    private func scoreRouteCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard !circles.isEmpty else { return 50 }
        guard !coordinates.isEmpty else { return 50 }

        let sampled = stride(from: 0, to: coordinates.count, by: 5).map { coordinates[$0] }
        guard !sampled.isEmpty else { return 50 }

        let totalScore = sampled.reduce(0.0) { total, coordinate in
            let pointLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let closest = circles.min(by: { a, b in
                let aLocation = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                let bLocation = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                return aLocation.distance(from: pointLocation) < bLocation.distance(from: pointLocation)
            }) else {
                return total + 50.0
            }

            let closestLocation = CLLocation(
                latitude: closest.coordinate.latitude,
                longitude: closest.coordinate.longitude
            )
            let distance = closestLocation.distance(from: pointLocation)
            return total + (distance <= closest.radius ? Double(closest.score) : 50.0)
        }

        return totalScore / Double(sampled.count)
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
                        }

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
