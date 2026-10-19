//
//  RoutePlanner.swift
//  connectivity
//
//  Finds driving routes, ranks them by signal along the way, and hands the
//  chosen one to Apple Maps or Google Maps without it being swapped for the
//  fastest route.
//
import Foundation
import MapKit
import Observation

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

enum RouteField: Hashable {
    case start
    case destination
}

enum NavigationApp: String, CaseIterable, Identifiable {
    case appleMaps
    case googleMaps

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleMaps: return "Apple Maps"
        case .googleMaps: return "Google Maps"
        }
    }
}

private enum RoutePlannerError: LocalizedError {
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

/// How a route fares against the signal map.
struct RouteSignalProfile: Equatable {
    /// Mean score along the route; stretches without data count as 50.
    let averageScore: Double
    /// Lowest score among stretches that do have data.
    let weakestScore: Int?
    /// Share of the route covered by tested areas, 0...1.
    let coverage: Double
}

struct RouteOption: Identifiable, Equatable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let travelTime: TimeInterval
    let distance: CLLocationDistance
    let signal: RouteSignalProfile
    let usesDataWaypoint: Bool

    /// Set once all options are known.
    fileprivate(set) var isFastest = false
    fileprivate(set) var isBestSignal = false
    /// Points along this route that make a navigation app follow it rather
    /// than its own fastest route. Empty for the fastest route itself.
    fileprivate(set) var viaPoints: [CLLocationCoordinate2D] = []

    var minutes: Int { max(1, Int((travelTime / 60).rounded())) }
    var averageScore: Int { Int(signal.averageScore.rounded()) }

    /// Average signal, pulled down by the worst stretch: a route that
    /// drops to a dead zone is worse than its average suggests.
    var signalQuality: Double {
        signal.averageScore * 0.7 + Double(signal.weakestScore ?? Int(signal.averageScore)) * 0.3
    }

    /// Signal quality minus one point per five minutes of driving.
    var selectionScore: Double {
        signalQuality - (travelTime / 300.0)
    }

    static func == (lhs: RouteOption, rhs: RouteOption) -> Bool {
        lhs.id == rhs.id
            && lhs.isFastest == rhs.isFastest
            && lhs.isBestSignal == rhs.isBestSignal
            && lhs.viaPoints.count == rhs.viaPoints.count
    }
}

/// Live address suggestions while typing, via `MKLocalSearchCompleter`.
@MainActor
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, near coordinate: CLLocationCoordinate2D?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            clear()
            return
        }
        if let coordinate {
            completer.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.cancel()
        results = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let latest = Array(completer.results.prefix(5))
        MainActor.assumeIsolated { results = latest }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { results = [] }
    }
}

@MainActor
@Observable
final class RoutePlanner {
    var startMode: RouteStartMode = .currentLocation
    var startQuery = ""
    var destinationQuery = ""

    private(set) var startCoordinate: CLLocationCoordinate2D?
    private(set) var endCoordinate: CLLocationCoordinate2D?
    private(set) var options: [RouteOption] = []
    var selectedOptionID: UUID?
    private(set) var isCalculating = false
    private(set) var errorMessage: String?

    /// Completions chosen from the suggestion list, so resolving them uses
    /// the exact place rather than re-searching the typed text.
    @ObservationIgnored private var pickedCompletion: [RouteField: PickedPlace] = [:]

    private struct PickedPlace {
        let completion: MKLocalSearchCompletion
        /// The text the pick wrote into the field.
        let text: String
    }
    @ObservationIgnored private var calculation: Task<Void, Never>?

    var selectedOption: RouteOption? {
        options.first { $0.id == selectedOptionID } ?? options.first
    }

    var alternateOptions: [RouteOption] {
        options.filter { $0.id != selectedOption?.id }
    }

    var hasInput: Bool {
        !startQuery.isEmpty || !destinationQuery.isEmpty || !options.isEmpty
    }

    var canCalculate: Bool {
        guard !isCalculating, !trimmed(destinationQuery).isEmpty else { return false }
        return startMode == .currentLocation || !trimmed(startQuery).isEmpty
    }

    // MARK: Editing

    func choose(_ completion: MKLocalSearchCompletion, for field: RouteField) {
        let text = completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle)"
        pickedCompletion[field] = PickedPlace(completion: completion, text: text)
        switch field {
        case .start: startQuery = text
        case .destination: destinationQuery = text
        }
    }

    /// Typing over a picked suggestion means the user wants something else.
    /// The change made by picking it is ignored.
    func textChanged(in field: RouteField) {
        let current = field == .start ? startQuery : destinationQuery
        guard pickedCompletion[field]?.text != current else { return }
        pickedCompletion[field] = nil
        invalidateResults()
    }

    func useCurrentLocation() {
        startMode = .currentLocation
        startQuery = ""
        pickedCompletion[.start] = nil
        invalidateResults()
    }

    func useCustomStart() {
        startMode = .customAddress
        invalidateResults()
    }

    /// Swaps start and destination. "My location" becomes the destination's
    /// text, so the start turns into a typed address.
    func swapEndpoints() {
        let oldDestination = destinationQuery
        let oldDestinationPick = pickedCompletion[.destination]

        if startMode == .currentLocation {
            destinationQuery = ""
            pickedCompletion[.destination] = nil
            startMode = .customAddress
        } else {
            destinationQuery = startQuery
            pickedCompletion[.destination] = pickedCompletion[.start]
        }

        startQuery = oldDestination
        pickedCompletion[.start] = oldDestinationPick
        invalidateResults()
    }

    func clear() {
        calculation?.cancel()
        startMode = .currentLocation
        startQuery = ""
        destinationQuery = ""
        pickedCompletion = [:]
        startCoordinate = nil
        endCoordinate = nil
        options = []
        selectedOptionID = nil
        errorMessage = nil
        isCalculating = false
    }

    private func invalidateResults() {
        guard !options.isEmpty || errorMessage != nil else { return }
        options = []
        selectedOptionID = nil
        errorMessage = nil
    }

    // MARK: Calculating

    func calculate(circles: [SignalCircle]) {
        guard canCalculate else { return }

        calculation?.cancel()
        isCalculating = true
        errorMessage = nil
        options = []
        selectedOptionID = nil

        let userCoordinate = UserStore.shared.hasFix ? UserStore.shared.coordinate : nil

        calculation = Task {
            do {
                let start: CLLocationCoordinate2D
                if startMode == .currentLocation {
                    guard let userCoordinate else { throw RoutePlannerError.currentLocationUnavailable }
                    start = userCoordinate
                } else {
                    start = try await resolve(.start, near: userCoordinate)
                }
                let end = try await resolve(.destination, near: start)

                let found = try await Self.findOptions(from: start, to: end, circles: circles)
                guard !Task.isCancelled else { return }

                startCoordinate = start
                endCoordinate = end
                options = found
                selectedOptionID = found.first?.id
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isCalculating = false
        }
    }

    private func resolve(_ field: RouteField, near coordinate: CLLocationCoordinate2D?) async throws -> CLLocationCoordinate2D {
        let request: MKLocalSearch.Request
        let query = trimmed(field == .start ? startQuery : destinationQuery)

        if let picked = pickedCompletion[field], picked.text == query {
            request = MKLocalSearch.Request(completion: picked.completion)
        } else {
            guard !query.isEmpty else {
                throw RoutePlannerError.emptyAddress(field == .start ? "start" : "destination")
            }
            request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let coordinate {
                request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
            }
        }
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw RoutePlannerError.locationNotFound(query)
        }
        return item.location.coordinate
    }

    // MARK: Route search

    nonisolated private struct Leg: Sendable {
        let coordinates: [CLLocationCoordinate2D]
        let travelTime: TimeInterval
        let distance: CLLocationDistance
    }

    /// Direct routes (with MapKit's alternates) plus detours through
    /// strong-signal areas, deduplicated and ranked best-first.
    private nonisolated static func findOptions(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        circles: [SignalCircle]
    ) async throws -> [RouteOption] {
        let waypoints = signalWaypointCandidates(from: start, to: end, circles: circles)

        let candidates: [(legs: [Leg], viaData: Bool)] = await withTaskGroup(of: [(legs: [Leg], viaData: Bool)].self) { group in
            group.addTask {
                let routes = (try? await legs(from: start, to: end, alternates: true)) ?? []
                return routes.map { (legs: [$0], viaData: false) }
            }
            for waypoint in waypoints {
                group.addTask {
                    guard let first = try? await legs(from: start, to: waypoint, alternates: false).first,
                          let second = try? await legs(from: waypoint, to: end, alternates: false).first else {
                        return []
                    }
                    return [(legs: [first, second], viaData: true)]
                }
            }

            var all: [(legs: [Leg], viaData: Bool)] = []
            for await result in group { all.append(contentsOf: result) }
            return all
        }

        var options = candidates.map { candidate -> RouteOption in
            let coordinates = candidate.legs.enumerated().flatMap { index, leg in
                index == 0 ? leg.coordinates : Array(leg.coordinates.dropFirst())
            }
            return RouteOption(
                coordinates: coordinates,
                travelTime: candidate.legs.reduce(0) { $0 + $1.travelTime },
                distance: candidate.legs.reduce(0) { $0 + $1.distance },
                signal: signalProfile(for: coordinates, circles: circles),
                usesDataWaypoint: candidate.viaData
            )
        }
        // A detour to a strong-signal spot that sits off to the side means
        // driving out and back the same road. It scores well (the good
        // stretch counts twice) but nobody wants to drive it.
        options.removeAll { $0.usesDataWaypoint && doublesBack($0.coordinates) }
        guard !options.isEmpty else { throw RoutePlannerError.noRoutesFound }

        options = deduplicated(options)
            .sorted { $0.selectionScore > $1.selectionScore }

        // Best signal, the fastest, and at most one more.
        let fastest = options.min { $0.travelTime < $1.travelTime }!
        var shown = Array(options.prefix(2))
        if !shown.contains(where: { $0.id == fastest.id }) {
            shown[shown.count - 1] = fastest
        }
        if options.count > 2, shown.count < 3,
           let extra = options.first(where: { option in !shown.contains { $0.id == option.id } }) {
            shown.append(extra)
        }

        // Exactly one "best signal", by the same measure the ranking uses.
        shown.sort { $0.selectionScore > $1.selectionScore }
        let bestSignal = shown.max { $0.signalQuality < $1.signalQuality }
        return shown.map { option in
            var option = option
            option.isFastest = option.id == fastest.id
            option.isBestSignal = option.id == bestSignal?.id && shown.count > 1
            option.viaPoints = option.isFastest ? [] : viaPoints(for: option.coordinates, against: fastest.coordinates)
            return option
        }
    }

    private nonisolated static func legs(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, alternates: Bool) async throws -> [Leg] {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = alternates

        let response = try await MKDirections(request: request).calculate()
        return response.routes.map { route in
            let count = route.polyline.pointCount
            var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: count)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
            return Leg(coordinates: coordinates, travelTime: route.expectedTravelTime, distance: route.distance)
        }
    }

    /// Detours through a data point often come back as the direct route.
    private nonisolated static func deduplicated(_ options: [RouteOption]) -> [RouteOption] {
        var kept: [RouteOption] = []
        for option in options.sorted(by: { $0.selectionScore > $1.selectionScore }) {
            let duplicate = kept.contains { existing in
                abs(existing.travelTime - option.travelTime) < 30
                    && abs(existing.distance - option.distance) < 150
            }
            if !duplicate { kept.append(option) }
        }
        return kept
    }

    // MARK: Handing off to a navigation app

    /// URL that opens `app` on the selected route. Through-points are added as
    /// stops; without them the app re-plans its own fastest route.
    func navigationURL(for app: NavigationApp) -> URL? {
        guard let option = selectedOption, let end = endCoordinate else { return nil }
        return Self.navigationURL(
            app: app,
            start: startMode == .currentLocation ? nil : startCoordinate,
            end: end,
            viaPoints: option.viaPoints
        )
    }

    /// `start` nil means the user's current location.
    nonisolated static func navigationURL(
        app: NavigationApp,
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D,
        viaPoints: [CLLocationCoordinate2D]
    ) -> URL? {
        let format: (CLLocationCoordinate2D) -> String = {
            String(format: "%.6f,%.6f", $0.latitude, $0.longitude)
        }

        switch app {
        case .appleMaps:
            // Unified Maps URL (iOS 18.4+); `waypoint` may repeat.
            var components = URLComponents(string: "https://maps.apple.com/directions")!
            var items: [URLQueryItem] = []
            if let start { items.append(URLQueryItem(name: "source", value: format(start))) }
            items.append(URLQueryItem(name: "destination", value: format(end)))
            items += viaPoints.map { URLQueryItem(name: "waypoint", value: format($0)) }
            items.append(URLQueryItem(name: "mode", value: "driving"))
            components.queryItems = items
            return components.url

        case .googleMaps:
            var components = URLComponents(string: "https://www.google.com/maps/dir/")!
            var items = [URLQueryItem(name: "api", value: "1")]
            if let start { items.append(URLQueryItem(name: "origin", value: format(start))) }
            items.append(URLQueryItem(name: "destination", value: format(end)))
            if !viaPoints.isEmpty {
                items.append(URLQueryItem(name: "waypoints", value: viaPoints.map(format).joined(separator: "|")))
            }
            items.append(URLQueryItem(name: "travelmode", value: "driving"))
            components.queryItems = items
            return components.url
        }
    }

    // MARK: Geometry

    /// Up to `maxCount` points where `route` strays furthest from `reference`,
    /// one per divergent stretch, in driving order. Pinning these is enough
    /// to keep a navigation app on `route`.
    nonisolated static func viaPoints(
        for route: [CLLocationCoordinate2D],
        against reference: [CLLocationCoordinate2D],
        maxCount: Int = 2,
        // Shared road measures ~0 m. A parallel street beside a freeway can
        // be under 150 m away, so the cut-off has to sit well below that.
        threshold: CLLocationDistance = 40
    ) -> [CLLocationCoordinate2D] {
        guard route.count > 2, reference.count > 1 else { return [] }

        let referencePoints = downsample(reference, to: 400).map(MKMapPoint.init)
        let samples = downsample(route, to: 160)

        // Contiguous stretches beyond `threshold`, keeping each one's peak.
        var peaks: [(index: Int, distance: CLLocationDistance)] = []
        var current: (index: Int, distance: CLLocationDistance)?

        for (index, coordinate) in samples.enumerated() {
            let deviation = distance(from: MKMapPoint(coordinate), toPolyline: referencePoints)
            if deviation > threshold {
                if current == nil || deviation > current!.distance {
                    current = (index, deviation)
                }
            } else if let peak = current {
                peaks.append(peak)
                current = nil
            }
        }
        if let peak = current { peaks.append(peak) }

        return peaks
            .sorted { $0.distance > $1.distance }
            .prefix(maxCount)
            .sorted { $0.index < $1.index }
            .map { samples[$0.index] }
    }

    /// True when the route comes back within `tolerance` of a stretch it
    /// already drove, at least `minimumGap` metres of driving later.
    nonisolated static func doublesBack(
        _ route: [CLLocationCoordinate2D],
        tolerance: CLLocationDistance = 40,
        minimumGap: CLLocationDistance = 600
    ) -> Bool {
        let points = downsample(route, to: 150).map(MKMapPoint.init)
        guard points.count > 3 else { return false }

        // Driven distance to each sample, so "later" means further along.
        var along = [0.0]
        for index in 1..<points.count {
            along.append(along[index - 1] + points[index - 1].distance(to: points[index]))
        }

        for j in 2..<points.count {
            for i in 1..<j where along[j] - along[i] > minimumGap {
                if distanceFromSegment(points[j], start: points[i - 1], end: points[i]) < tolerance {
                    return true
                }
            }
        }
        return false
    }

    private nonisolated static func downsample(_ coordinates: [CLLocationCoordinate2D], to limit: Int) -> [CLLocationCoordinate2D] {
        guard coordinates.count > limit else { return coordinates }
        let step = Double(coordinates.count - 1) / Double(limit - 1)
        return (0..<limit).map { coordinates[Int((Double($0) * step).rounded())] }
    }

    private nonisolated static func distance(from point: MKMapPoint, toPolyline polyline: [MKMapPoint]) -> CLLocationDistance {
        var best = CLLocationDistance.greatestFiniteMagnitude
        for index in 1..<polyline.count {
            best = min(best, distanceFromSegment(point, start: polyline[index - 1], end: polyline[index]))
        }
        return best
    }

    // MARK: Signal scoring

    nonisolated static func signalProfile(for coordinates: [CLLocationCoordinate2D], circles: [SignalCircle]) -> RouteSignalProfile {
        // Routes can be thousands of points; ~120 evenly spaced samples is
        // plenty to score them and keeps this fast on large maps.
        let sampled = downsample(coordinates, to: 120)
        guard !circles.isEmpty, !sampled.isEmpty else {
            return RouteSignalProfile(averageScore: 50, weakestScore: nil, coverage: 0)
        }

        let scores = sampled.map { coveringSignalScore(at: $0, in: circles, tolerance: routeMatchTolerance) }
        let covered = scores.compactMap { $0 }
        let total = scores.reduce(0.0) { $0 + Double($1 ?? 50) }

        return RouteSignalProfile(
            averageScore: total / Double(sampled.count),
            weakestScore: covered.min(),
            coverage: Double(covered.count) / Double(sampled.count)
        )
    }

    /// Strong-signal points near the straight line between the endpoints,
    /// spread apart, to try as detour waypoints.
    private nonisolated static func signalWaypointCandidates(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        circles: [SignalCircle]
    ) -> [CLLocationCoordinate2D] {
        guard !circles.isEmpty else { return [] }

        let startPoint = MKMapPoint(start)
        let endPoint = MKMapPoint(end)
        let directDistance = max(startPoint.distance(to: endPoint), 1)
        let corridorWidth = min(max(directDistance * 0.25, 750), 5_000)
        let maxAddedDistance = max(directDistance * 0.75, 2_000)

        let ranked = circles
            .filter { $0.score >= 55 }
            .compactMap { circle -> (coordinate: CLLocationCoordinate2D, rank: Double)? in
                let point = MKMapPoint(circle.coordinate)
                let progress = routeProgress(for: point, from: startPoint, to: endPoint)
                guard (0.08...0.92).contains(progress) else { return nil }

                let distanceFromRoute = distanceFromSegment(point, start: startPoint, end: endPoint)
                guard distanceFromRoute <= corridorWidth else { return nil }

                let addedDistance = startPoint.distance(to: point) + point.distance(to: endPoint) - directDistance
                guard addedDistance <= maxAddedDistance else { return nil }

                let rank = Double(circle.score) * 4.0 - (distanceFromRoute / 120.0) - (addedDistance / 250.0)
                return (circle.coordinate, rank)
            }
            .sorted { $0.rank > $1.rank }

        var selected: [CLLocationCoordinate2D] = []
        for candidate in ranked {
            let point = MKMapPoint(candidate.coordinate)
            if !selected.contains(where: { MKMapPoint($0).distance(to: point) < 600 }) {
                selected.append(candidate.coordinate)
            }
            if selected.count == 6 { break }
        }
        return selected
    }

    private nonisolated static func routeProgress(for point: MKMapPoint, from start: MKMapPoint, to end: MKMapPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }

        let progress = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        return min(max(progress, 0), 1)
    }

    private nonisolated static func distanceFromSegment(_ point: MKMapPoint, start: MKMapPoint, end: MKMapPoint) -> CLLocationDistance {
        let progress = routeProgress(for: point, from: start, to: end)
        let projected = MKMapPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
        return point.distance(to: projected)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
