//
//  RouteBuilderView.swift
//  connectivity
//
//  Full-screen route planner: endpoints with live suggestions, route options
//  ranked by signal, and hand-off to a navigation app on the chosen route.
//
import SwiftUI
import MapKit

struct RouteBuilderView: View {
    @Bindable var planner: RoutePlanner
    @Binding var circles: [SignalCircle]
    let dataDisplayMode: SignalDataDisplayMode
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var completer = AddressCompleter()
    @State private var recenterMap = false
    @State private var sheetHeight: CGFloat = 320
    @FocusState private var focusedField: RouteField?

    private var showsSuggestions: Bool {
        focusedField != nil && !completer.results.isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            ConnectivityMapView(
                startPoint: .constant(planner.startCoordinate),
                endPoint: .constant(planner.endCoordinate),
                circles: $circles,
                routeCoordinates: planner.selectedOption?.coordinates ?? [],
                alternateRouteCoordinates: planner.alternateOptions.map(\.coordinates),
                onSelectAlternateRoute: { index in
                    let alternates = planner.alternateOptions
                    guard alternates.indices.contains(index) else { return }
                    select(alternates[index])
                },
                routeFramingInsets: UIEdgeInsets(top: 130, left: 40, bottom: sheetHeight + 24, right: 40),
                dataDisplayMode: dataDisplayMode,
                showsRouteBuilderOverlays: true,
                allowsRoutePointSelection: false,
                bottomChromeInset: sheetHeight,
                recenterMap: $recenterMap
            )
            .ignoresSafeArea()
            .onTapGesture { focusedField = nil }

            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                sheet
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
            }
            // Only the container region: the sheet should still ride up
            // with the keyboard while editing.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .foregroundStyle(.white)
        .onChange(of: planner.startQuery) { _, query in
            guard focusedField == .start else { return }
            planner.textChanged(in: .start)
            completer.update(query: query, near: userCoordinate)
        }
        .onChange(of: planner.destinationQuery) { _, query in
            guard focusedField == .destination else { return }
            planner.textChanged(in: .destination)
            completer.update(query: query, near: userCoordinate)
        }
        .onChange(of: focusedField) { _, _ in completer.clear() }
        .sensoryFeedback(.success, trigger: planner.options.count) { old, new in old == 0 && new > 0 }
        .sensoryFeedback(.error, trigger: planner.errorMessage) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: planner.selectedOptionID)
        .onAppear {
            if planner.destinationQuery.isEmpty { focusedField = .destination }
        }
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        UserStore.shared.hasFix ? UserStore.shared.coordinate : nil
    }

    // MARK: Header

    private var header: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 10) {
                GlassIconButton(systemName: "chevron.left", diameter: 44, tint: .white, action: onClose)
                    .accessibilityLabel("Close route planner")

                VStack(alignment: .leading, spacing: 1) {
                    Text("ROUTE PLANNER")
                        .font(.ds(9, .bold))
                        .tracking(1.3)
                        .foregroundStyle(AppTheme.muted)
                    Text("Stay connected")
                        .font(.ds(16, .bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular, in: Capsule())

                Spacer(minLength: 0)

                GlassIconButton(systemName: "location.fill", diameter: 44) {
                    recenterMap = true
                }
                .accessibilityLabel("Recenter map")
            }
        }
        .padding(.top, 4)
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: planner.options.isEmpty ? 14 : 10) {
            Capsule()
                .fill(Color.white.opacity(0.26))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(planner.options.isEmpty ? "Where to?" : "Choose a route")
                        .font(.ds(22, .bold))
                        .contentTransition(.interpolate)
                    if planner.options.isEmpty {
                        Text("We'll find the path with the best signal")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                Spacer()

                if planner.hasInput {
                    Button("Clear") {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                            planner.clear()
                        }
                        completer.clear()
                    }
                    .font(.ds(14, .bold))
                    .foregroundStyle(AppTheme.accent)
                    .buttonStyle(.plain)
                }
            }

            endpointsCard

            if showsSuggestions {
                suggestionsList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !planner.options.isEmpty {
                routeOptionsList
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if let error = planner.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.bad)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !showsSuggestions {
                primaryAction
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: planner.options)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showsSuggestions)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: planner.isCalculating)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        // Extra bottom padding clears the home indicator, since the sheet's
        // glass is extended past the safe area to meet the screen edge. When
        // the keyboard is up the sheet sits on it, so less is needed.
        .padding(.bottom, focusedField == nil ? 40 : 14)
        .glassEffect(.regular, in: sheetShape)
        .overlay(alignment: .top) {
            sheetShape.strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 26, y: -10)
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 32,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 32,
            style: .continuous
        )
    }

    // MARK: Endpoints

    /// Start and destination stacked like a trip, joined by a dotted line,
    /// with a swap button on the side.
    private var endpointsCard: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Circle()
                    .fill(AppTheme.good)
                    .frame(width: 10, height: 10)
                    .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2) }
                    .shadow(color: AppTheme.good, radius: 4)

                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(AppTheme.muted.opacity(0.6)).frame(width: 2.5, height: 2.5)
                    }
                }

                Image(systemName: "mappin")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.warn)
                    .shadow(color: AppTheme.warn, radius: 4)
            }
            .frame(width: 16)

            VStack(spacing: 0) {
                startRow
                GlassDivider(inset: 0)
                destinationRow
            }

            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                    planner.swapEndpoints()
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .glassEffect(.clear.interactive(), in: Circle())
            .disabled(planner.startMode == .currentLocation && planner.destinationQuery.isEmpty)
            .accessibilityLabel("Swap start and destination")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var startRow: some View {
        if planner.startMode == .currentLocation {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    planner.useCustomStart()
                }
                focusedField = .start
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("My location")
                        .font(.ds(15, .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("Change")
                        .font(.ds(12, .bold))
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                TextField("Starting point", text: $planner.startQuery)
                    .font(.ds(15, .medium))
                    .tint(AppTheme.accent)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .start)
                    .onSubmit { focusedField = .destination }

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        planner.useCurrentLocation()
                    }
                    if focusedField == .start { focusedField = nil }
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start from my location")
            }
            .frame(height: rowHeight)
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 8) {
            TextField("Search for a place or address", text: $planner.destinationQuery)
                .font(.ds(15, .medium))
                .tint(AppTheme.accent)
                .textInputAutocapitalization(.words)
                .submitLabel(.route)
                .focused($focusedField, equals: .destination)
                .onSubmit(calculate)

            if !planner.destinationQuery.isEmpty && focusedField == .destination {
                Button {
                    planner.destinationQuery = ""
                    planner.textChanged(in: .destination)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear destination")
            }
        }
        .frame(height: rowHeight)
    }

    private var rowHeight: CGFloat {
        planner.options.isEmpty ? 46 : 38
    }

    // MARK: Suggestions

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(completer.results.enumerated()), id: \.offset) { index, completion in
                Button {
                    pick(completion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: completion.subtitle.isEmpty ? "magnifyingglass" : "mappin.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .font(.ds(15, .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.ds(12, .medium))
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.muted.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < completer.results.count - 1 {
                    GlassDivider(inset: 50)
                }
            }
        }
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        guard let field = focusedField else { return }
        planner.choose(completion, for: field)
        completer.clear()

        if field == .start, planner.destinationQuery.isEmpty {
            focusedField = .destination
        } else {
            focusedField = nil
            calculate()
        }
    }

    // MARK: Route options

    private var routeOptionsList: some View {
        VStack(spacing: 8) {
            ForEach(planner.options) { option in
                RouteOptionRow(
                    option: option,
                    isSelected: option.id == planner.selectedOption?.id,
                    fastestMinutes: planner.options.first(where: \.isFastest)?.minutes
                ) {
                    select(option)
                }
            }
        }
    }

    private func select(_ option: RouteOption) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            planner.selectedOptionID = option.id
        }
    }

    // MARK: Primary action

    @ViewBuilder
    private var primaryAction: some View {
        if planner.selectedOption != nil {
            VStack(spacing: 8) {
                Menu {
                    ForEach(NavigationApp.allCases) { app in
                        Button {
                            navigate(with: app)
                        } label: {
                            Label(app.label, systemImage: app == .appleMaps ? "map.fill" : "globe")
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("Navigate this route")
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(0.7)
                    }
                    .font(.ds(16, .bold))
                    .foregroundStyle(AppTheme.bgDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
                }
                .glassEffect(.regular.tint(AppTheme.accent).interactive(), in: Capsule())

                if let option = planner.selectedOption, !option.viaPoints.isEmpty {
                    Label(
                        "Adds \(option.viaPoints.count) stop\(option.viaPoints.count == 1 ? "" : "s") so Maps follows this route instead of its own fastest",
                        systemImage: "info.circle"
                    )
                    .font(.ds(11, .medium))
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            Button(action: calculate) {
                HStack(spacing: 9) {
                    if planner.isCalculating {
                        ProgressView().tint(AppTheme.bgDeep)
                        Text("Scanning routes…")
                    } else {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        Text("Find routes")
                    }
                }
                .font(.ds(16, .bold))
                .foregroundStyle(AppTheme.bgDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.accent)
            .disabled(!planner.canCalculate)
            .opacity(planner.canCalculate || planner.isCalculating ? 1 : 0.5)
        }
    }

    private func calculate() {
        focusedField = nil
        completer.clear()
        planner.calculate(circles: circles)
    }

    private func navigate(with app: NavigationApp) {
        guard let url = planner.navigationURL(for: app) else { return }
        openURL(url)
    }
}

// MARK: - Option row

private struct RouteOptionRow: View {
    let option: RouteOption
    let isSelected: Bool
    let fastestMinutes: Int?
    let onSelect: () -> Void

    private var tint: Color { colorForScore(option.averageScore) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                ScoreRing(score: option.averageScore, diameter: 40, lineWidth: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(option.minutes)")
                            .font(.dsMono(18, .bold))
                            .foregroundStyle(.white)
                        Text("min")
                            .font(.ds(12, .semibold))
                            .foregroundStyle(AppTheme.muted)

                        Text("· " + formattedDistance)
                            .font(.ds(12, .semibold))
                            .foregroundStyle(AppTheme.muted)

                        if let extra = extraMinutes {
                            Text("+\(extra) min")
                                .font(.dsMono(11, .bold))
                                .foregroundStyle(AppTheme.warn)
                        }
                    }

                    HStack(spacing: 5) {
                        if option.isBestSignal {
                            GlassBadge(text: "Best signal", systemImage: "antenna.radiowaves.left.and.right", tint: AppTheme.good)
                        }
                        if option.isFastest {
                            GlassBadge(text: "Fastest", systemImage: "bolt.fill", tint: AppTheme.accent)
                        }
                        if let weakest = option.signal.weakestScore {
                            GlassBadge(text: "Low \(weakest)", tint: colorForScore(weakest))
                        } else {
                            GlassBadge(text: "No data", tint: AppTheme.muted)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.muted.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .glassEffect(
            .clear.tint(isSelected ? tint.opacity(0.16) : nil),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.6) : AppTheme.hairline, lineWidth: isSelected ? 1.5 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var extraMinutes: Int? {
        guard !option.isFastest, let fastestMinutes, option.minutes > fastestMinutes else { return nil }
        return option.minutes - fastestMinutes
    }

    private var formattedDistance: String {
        Measurement(value: option.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
