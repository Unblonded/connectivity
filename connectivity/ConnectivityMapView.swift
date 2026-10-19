//
//  ConnectivityMapView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import SwiftUI
import MapKit

/// Equality is by value so an unchanged reload does not redraw the map.
struct SignalCircle: Equatable {
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let score: Int   // 0...100, from speedScore

    static func == (lhs: SignalCircle, rhs: SignalCircle) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.radius == rhs.radius
            && lhs.score == rhs.score
    }
}

struct SignalCircleJSON: Codable {
    let id: Int
    let loc: Location
    let radius: Double
    let speed: Speed
    let sampleCount: Int

    struct Location: Codable {
        let lat: Double
        let lon: Double
    }

    struct Speed: Codable {
        let uploadMbps: Double
        let downloadMbps: Double
    }

    func toSignalCircle() -> SignalCircle {
        SignalCircle(
            coordinate: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lon),
            radius: radius,
            score: speedScore(d: speed.downloadMbps, u: speed.uploadMbps)
        )
    }
}

struct OutageReport: Codable, Identifiable {
    let id: Int
    let username: String
    let location: Location
    let message: String
    let timestamp: Int64

    struct Location: Codable {
        let lat: Double
        let lon: Double
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)
    }
}

final class OutageReportAnnotation: NSObject, MKAnnotation {
    let reportID: Int
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(report: OutageReport) {
        reportID = report.id
        coordinate = report.coordinate
        title = "Reported outage"
        subtitle = report.message
    }
}

final class SpeedLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let score: Int

    init(coordinate: CLLocationCoordinate2D, score: Int) {
        self.coordinate = coordinate
        self.score = score
    }
}

final class RoutePointAnnotation: MKPointAnnotation {
    let isStart: Bool

    init(coordinate: CLLocationCoordinate2D, isStart: Bool) {
        self.isStart = isStart
        super.init()
        self.coordinate = coordinate
        self.title = isStart ? "Start" : "End"
    }
}

/// Identity of a score chip, used to diff annotations between updates.
private struct SpeedLabelKey: Hashable {
    let latitude: Double
    let longitude: Double
    let score: Int

    init(_ circle: SignalCircle) {
        latitude = circle.coordinate.latitude
        longitude = circle.coordinate.longitude
        score = circle.score
    }
}

private struct RouteState: Equatable {
    let start: CLLocationCoordinate2D?
    let end: CLLocationCoordinate2D?
    let coordinates: [CLLocationCoordinate2D]
    let alternates: [[CLLocationCoordinate2D]]

    static func == (lhs: RouteState, rhs: RouteState) -> Bool {
        same(lhs.start, rhs.start)
            && same(lhs.end, rhs.end)
            && sameLine(lhs.coordinates, rhs.coordinates)
            && lhs.alternates.count == rhs.alternates.count
            && zip(lhs.alternates, rhs.alternates).allSatisfy { sameLine($0, $1) }
    }

    /// True when only the highlighted route changed, not the set of routes.
    func hasSameRoutes(as other: RouteState) -> Bool {
        let mine = ([coordinates] + alternates).map(\.count).sorted()
        let theirs = ([other.coordinates] + other.alternates).map(\.count).sorted()
        return Self.same(start, other.start) && Self.same(end, other.end) && mine == theirs
    }

    private static func sameLine(_ a: [CLLocationCoordinate2D], _ b: [CLLocationCoordinate2D]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { same($0, $1) }
    }

    private static func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
        a?.latitude == b?.latitude && a?.longitude == b?.longitude
    }
}

enum SignalDataDisplayMode: String, CaseIterable, Identifiable {
    case onlyCircles
    case onlyNumbers
    case numbersAndCircles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onlyCircles: return "Circles"
        case .onlyNumbers: return "Numbers"
        case .numbersAndCircles: return "Both"
        }
    }

    var showsCircles: Bool {
        self == .onlyCircles || self == .numbersAndCircles
    }

    var showsNumbers: Bool {
        self == .onlyNumbers || self == .numbersAndCircles
    }
}

// UIColor gradient version of colorForScore (UIKit context, not SwiftUI)
func uiColorForScore(_ score: Int) -> UIColor {
    let t = max(0.0, min(1.0, Double(score) / 100.0))

    let dead:  (r: CGFloat, g: CGFloat, b: CGFloat) = (1.00, 0.42, 0.42)
    let poor:  (r: CGFloat, g: CGFloat, b: CGFloat) = (1.00, 0.60, 0.30)
    let good:  (r: CGFloat, g: CGFloat, b: CGFloat) = (0.09, 0.78, 0.48)

    let (from, to, localT): ((r: CGFloat, g: CGFloat, b: CGFloat), (r: CGFloat, g: CGFloat, b: CGFloat), Double) =
        t < 0.5
        ? (dead, poor, t / 0.5)
        : (poor, good, (t - 0.5) / 0.5)

    let lt = CGFloat(localT)
    let r = from.r + (to.r - from.r) * lt
    let g = from.g + (to.g - from.g) * lt
    let b = from.b + (to.b - from.b) * lt

    return UIColor(red: r, green: g, blue: b, alpha: 1.0)
}

/// Score of the tested area covering `coordinate`, or nil when no tested
/// area reaches it. The nearest covering circle wins where several overlap.
/// `tolerance` widens every circle, e.g. for road geometry that runs a lane
/// or two away from where readings were taken.
func coveringSignalScore(
    at coordinate: CLLocationCoordinate2D,
    in circles: [SignalCircle],
    tolerance: CLLocationDistance = 0
) -> Int? {
    let point = MKMapPoint(coordinate)
    var best: (distance: CLLocationDistance, score: Int)?

    for circle in circles {
        let distance = point.distance(to: MKMapPoint(circle.coordinate))
        guard distance <= circle.radius + tolerance else { continue }
        if best == nil || distance < best!.distance {
            best = (distance, circle.score)
        }
    }

    return best?.score
}

// MARK: - Zoom generalisation

/// Merges circles into grid cells sized to the current zoom, so the amount of
/// map work tracks what fits on screen rather than how much data exists.
///
/// The grid is anchored to absolute map points and its cell size snaps to
/// powers of two, so panning never reshuffles clusters and they only change
/// when the zoom crosses a step.
enum SignalGeneralizer {
    struct Level: Hashable {
        /// Grid cell edge in map points; 0 means show raw data.
        let cellSize: Double
    }

    /// Picks a cell size giving roughly `divisions` cells across the view.
    /// Falls back to raw data once a cell would be smaller than
    /// `rawBelowMeters`, since by then points no longer crowd each other.
    static func level(for visibleRect: MKMapRect, divisions: Double, rawBelowMeters: Double) -> Level {
        guard visibleRect.width > 0, !visibleRect.isNull else { return Level(cellSize: 0) }

        let cellSize = pow(2, floor(log2(visibleRect.width / divisions)))
        let latitude = MKMapPoint(x: visibleRect.midX, y: visibleRect.midY).coordinate.latitude
        let cellMeters = cellSize / MKMapPointsPerMeterAtLatitude(latitude)

        return Level(cellSize: cellMeters < rawBelowMeters ? 0 : cellSize)
    }

    static func generalize(_ circles: [SignalCircle], at level: Level) -> [SignalCircle] {
        guard level.cellSize > 0 else { return circles }

        struct Cell: Hashable { let x: Int; let y: Int }
        struct Bucket {
            var sumX = 0.0, sumY = 0.0, sumScore = 0
            var maxRadius = 0.0
            var members: [MKMapPoint] = []
        }

        var buckets: [Cell: Bucket] = [:]
        buckets.reserveCapacity(min(circles.count, 4096))

        for circle in circles {
            let point = MKMapPoint(circle.coordinate)
            let cell = Cell(x: Int(floor(point.x / level.cellSize)), y: Int(floor(point.y / level.cellSize)))
            var bucket = buckets[cell, default: Bucket()]
            bucket.sumX += point.x
            bucket.sumY += point.y
            bucket.sumScore += circle.score
            bucket.maxRadius = max(bucket.maxRadius, circle.radius)
            bucket.members.append(point)
            buckets[cell] = bucket
        }

        return buckets.values.map { bucket in
            let count = Double(bucket.members.count)
            let center = MKMapPoint(x: bucket.sumX / count, y: bucket.sumY / count)
            let score = Int((Double(bucket.sumScore) / count).rounded())

            guard bucket.members.count > 1 else {
                return SignalCircle(coordinate: center.coordinate, radius: bucket.maxRadius, score: score)
            }

            // Cover the members' actual spread, but never spill far past the
            // cell, so a cluster cannot claim coverage it does not have.
            let spread = bucket.members.map { center.distance(to: $0) }.max() ?? 0
            let cellMeters = level.cellSize / MKMapPointsPerMeterAtLatitude(center.coordinate.latitude)
            let radius = min(spread + bucket.maxRadius, cellMeters * 0.75)

            return SignalCircle(coordinate: center.coordinate, radius: max(radius, bucket.maxRadius), score: score)
        }
    }
}

// MARK: - Heat map overlay

/// Every signal circle in one overlay, drawn by one renderer.
///
/// One `MKCircle` per data point costs MapKit an overlay, a renderer and a
/// tile pass each; with a few thousand points that is what made panning
/// stutter on older phones. Here each tile only walks a flat array and skips
/// whatever does not intersect it.
final class SignalHeatmapOverlay: NSObject, MKOverlay {
    struct Spot {
        let center: MKMapPoint
        let radius: Double   // in map points
        let bucket: Int      // index into the shared gradient table
        var rect: MKMapRect {
            MKMapRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    let spots: [Spot]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(circles: [SignalCircle]) {
        // Lower scores first so strong signal paints on top where areas overlap.
        spots = circles
            .sorted { $0.score < $1.score }
            .map { circle in
                let center = MKMapPoint(circle.coordinate)
                return Spot(
                    center: center,
                    radius: circle.radius * MKMapPointsPerMeterAtLatitude(circle.coordinate.latitude),
                    bucket: SignalHeatmapRenderer.bucket(for: circle.score)
                )
            }

        boundingMapRect = spots.reduce(MKMapRect.null) { $0.union($1.rect) }
        coordinate = boundingMapRect.isNull ? kCLLocationCoordinate2DInvalid : MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
        super.init()
    }
}

final class SignalHeatmapRenderer: MKOverlayRenderer {
    /// One prebuilt gradient per 5-point score band, shared by every tile.
    private static let bucketCount = 21
    private static let gradients: [CGGradient] = (0..<bucketCount).map { index in
        let color = uiColorForScore(index * 5)
        let colors = [
            color.withAlphaComponent(0.50).cgColor,
            color.withAlphaComponent(0.30).cgColor,
            color.withAlphaComponent(0.06).cgColor
        ] as CFArray
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    }
    private static let rimColors: [CGColor] = (0..<bucketCount).map {
        uiColorForScore($0 * 5).withAlphaComponent(0.55).cgColor
    }
    private static let dotColors: [CGColor] = (0..<bucketCount).map {
        uiColorForScore($0 * 5).withAlphaComponent(0.7).cgColor
    }

    static func bucket(for score: Int) -> Int {
        max(0, min(bucketCount - 1, Int((Double(score) / 5).rounded())))
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? SignalHeatmapOverlay else { return }

        let lineWidth = 1.2 / zoomScale
        // Below a few screen points a gradient is invisible work; draw a dot.
        let minimumGradientRadius = 3 / zoomScale

        for spot in overlay.spots {
            let spotRect = spot.rect
            guard spotRect.intersects(mapRect) else { continue }

            let rect = self.rect(for: spotRect)

            if spot.radius < minimumGradientRadius {
                context.setFillColor(Self.dotColors[spot.bucket])
                context.fillEllipse(in: rect)
                continue
            }

            let center = CGPoint(x: rect.midX, y: rect.midY)

            context.saveGState()
            context.addEllipse(in: rect)
            context.clip()
            context.drawRadialGradient(
                Self.gradients[spot.bucket],
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: rect.width / 2,
                options: []
            )
            context.restoreGState()

            context.setStrokeColor(Self.rimColors[spot.bucket])
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
    }
}

// MARK: - Route overlays

/// How far off a tested circle a route point may be and still take its score.
let routeMatchTolerance: CLLocationDistance = 60

/// Wide, translucent pass drawn under the route's core line.
final class RouteGlowPolyline: MKPolyline {}

/// A route the user has not selected: drawn muted, tappable to select.
final class AlternateRoutePolyline: MKPolyline {
    var index = 0
}

/// Route core line, coloured along its length by the signal it passes through.
/// Stretches with no tested data stay in the accent colour.
final class SignalRoutePolyline: MKPolyline {
    private(set) var stopColors: [UIColor] = []
    private(set) var stopLocations: [CGFloat] = []

    static let unknownColor = UIColor(red: 0.64, green: 0.90, blue: 1.00, alpha: 0.95)

    static func make(coordinates: [CLLocationCoordinate2D], circles: [SignalCircle]) -> SignalRoutePolyline {
        let line = SignalRoutePolyline(coordinates: coordinates, count: coordinates.count)
        let lastIndex = coordinates.count - 1
        let stopCount = min(coordinates.count, 64)

        for stop in 0..<stopCount {
            let fraction = stopCount == 1 ? 0 : Double(stop) / Double(stopCount - 1)
            let index = Int((fraction * Double(lastIndex)).rounded())
            let score = coveringSignalScore(at: coordinates[index], in: circles, tolerance: routeMatchTolerance)

            line.stopColors.append(score.map(uiColorForScore) ?? unknownColor)
            line.stopLocations.append(CGFloat(fraction))
        }

        return line
    }
}

// MARK: - Score chips

/// Score bubble on the map.
///
/// Plain layers rather than a blur view: a live `UIVisualEffectView` per chip
/// was the single most expensive thing on the map, since every one re-samples
/// the tiles beneath it on each frame of a pan.
final class SignalScoreAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "signalScore"

    private let disc = UIView()
    private let scoreLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        centerOffset = .zero
        backgroundColor = .clear
        // Lets MapKit hide chips that would overlap, instead of stacking
        // hundreds of them when zoomed out.
        collisionMode = .circle
        displayPriority = .defaultHigh

        disc.frame = bounds
        disc.layer.cornerRadius = bounds.width / 2
        disc.layer.borderWidth = 1.5
        disc.isUserInteractionEnabled = false
        addSubview(disc)

        scoreLabel.frame = bounds
        scoreLabel.textAlignment = .center
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        scoreLabel.textColor = .white
        addSubview(scoreLabel)

        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
        layer.shadowOffset = .zero
        layer.shadowRadius = 5
        layer.shadowOpacity = 0.45
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(score: Int) {
        let color = uiColorForScore(score)
        scoreLabel.text = "\(score)"
        disc.layer.borderColor = color.cgColor
        disc.backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 0.78)
            .blended(with: color, fraction: 0.28)
        layer.shadowColor = color.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        layer.removeAllAnimations()
        transform = .identity
        alpha = 1
    }

    /// Springs the chip in from a small dot when new data lands on the map.
    func popIn(delay: TimeInterval) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        alpha = 0
        UIView.animate(
            withDuration: 0.5,
            delay: delay,
            usingSpringWithDamping: 0.62,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}

private extension UIColor {
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * fraction,
            green: g1 + (g2 - g1) * fraction,
            blue: b1 + (b2 - b1) * fraction,
            alpha: a1
        )
    }
}

// MARK: - Map view

struct ConnectivityMapView: UIViewRepresentable {
    @Binding var startPoint: CLLocationCoordinate2D?
    @Binding var endPoint: CLLocationCoordinate2D?
    @Binding var circles: [SignalCircle]
    var routeCoordinates: [CLLocationCoordinate2D]
    /// Other route options, drawn muted under the selected one.
    var alternateRouteCoordinates: [[CLLocationCoordinate2D]] = []
    /// Called with an index into `alternateRouteCoordinates` when one is tapped.
    var onSelectAlternateRoute: ((Int) -> Void)? = nil
    /// When set, the camera frames new routes inside these insets.
    var routeFramingInsets: UIEdgeInsets? = nil
    var dataDisplayMode: SignalDataDisplayMode = .numbersAndCircles
    var showsRouteBuilderOverlays: Bool = true
    var allowsRoutePointSelection: Bool = true
    var onMapTap: ((CLLocationCoordinate2D) -> Void)? = nil
    var outageReports: [OutageReport] = []
    /// Lifts MapKit's legal attribution above any chrome floating over the map.
    var bottomChromeInset: CGFloat = 0
    @Binding var recenterMap: Bool

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator

        // Dark, de-emphasised basemap: the signal data should be the brightest
        // thing on screen, not the road network.
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.overrideUserInterfaceStyle = .dark

        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = false
        map.userTrackingMode = .follow

        map.register(SignalScoreAnnotationView.self, forAnnotationViewWithReuseIdentifier: SignalScoreAnnotationView.reuseIdentifier)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)

        return map
    }

    /// Called on every SwiftUI pass (the parent re-renders once a second), so
    /// each layer is only rebuilt when its own inputs changed.
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Capped so a tall sheet cannot squeeze the map's usable area to
        // nothing; MapKit centres and frames inside these margins.
        let maxBottom = map.bounds.height > 0 ? map.bounds.height * 0.5 : bottomChromeInset
        let margins = UIEdgeInsets(top: 0, left: 0, bottom: min(bottomChromeInset, maxBottom), right: 0)
        if map.layoutMargins != margins {
            map.layoutMargins = margins
        }

        if recenterMap {
            let coord = UserStore.shared.coordinate
            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            map.setRegion(region, animated: true)
            DispatchQueue.main.async { self.recenterMap = false }
        }

        let circlesChanged = coordinator.lastCircles != circles
        let modeChanged = coordinator.lastDisplayMode != dataDisplayMode
        if circlesChanged || modeChanged {
            coordinator.lastCircles = circles
            coordinator.lastDisplayMode = dataDisplayMode
            coordinator.applyGeneralization(on: map, dataChanged: true)
        }

        let outageIDs = outageReports.map(\.id)
        if coordinator.lastOutageIDs != outageIDs {
            coordinator.lastOutageIDs = outageIDs
            coordinator.updateOutages(on: map, reports: outageReports)
        }

        let route = showsRouteBuilderOverlays
            ? RouteState(start: startPoint, end: endPoint, coordinates: routeCoordinates, alternates: alternateRouteCoordinates)
            : RouteState(start: nil, end: nil, coordinates: [], alternates: [])
        // The route colouring reads the circles, so it follows them too.
        if coordinator.lastRoute != route || (circlesChanged && route.coordinates.count > 1) {
            let isNewRouteSet = !(coordinator.lastRoute?.hasSameRoutes(as: route) ?? false)
            coordinator.lastRoute = route
            coordinator.updateRoute(on: map, route: route, circles: circles)

            // Re-frame for a new set of routes, but not when the user just
            // picked a different one of them.
            if isNewRouteSet, let insets = routeFramingInsets {
                coordinator.frameRoutes(on: map, route: route, insets: insets)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ConnectivityMapView
        private var hasCenteredOnce = false

        fileprivate var lastCircles: [SignalCircle]?
        fileprivate var lastDisplayMode: SignalDataDisplayMode?
        fileprivate var lastOutageIDs: [Int]?
        fileprivate var lastRoute: RouteState?

        private var heatmap: SignalHeatmapOverlay?
        private var scoreLabels: [SpeedLabelKey: SpeedLabelAnnotation] = [:]
        private var outageAnnotations: [OutageReportAnnotation] = []
        private var routeAnnotations: [RoutePointAnnotation] = []
        private var routeOverlays: [MKOverlay] = []

        /// Chips added by the latest data change, which get the pop-in when
        /// MapKit first asks for their view. Chips merely scrolled back into
        /// view do not, so panning stays cheap.
        private var pendingPopIn = Set<ObjectIdentifier>()
        private static let popInLimit = 80

        /// Cell density for each layer. Heat blobs can sit close together;
        /// chips are ~36 pt wide so they need far fewer cells across.
        private static let heatDivisions = 28.0
        private static let chipDivisions = 7.0

        private var heatLevel: SignalGeneralizer.Level?
        private var chipLevel: SignalGeneralizer.Level?
        /// Generalised results per level, so zooming back and forth is free.
        private var generalizedCache: [SignalGeneralizer.Level: [SignalCircle]] = [:]

        init(_ parent: ConnectivityMapView) { self.parent = parent }

        /// Re-clusters both data layers for the current zoom. Cheap to call on
        /// every region change: it returns early unless a zoom step was crossed.
        func applyGeneralization(on map: MKMapView, dataChanged: Bool = false) {
            guard let circles = lastCircles, let mode = lastDisplayMode else { return }

            if dataChanged {
                generalizedCache = [:]
            }

            let visible = map.visibleMapRect
            let newHeat = SignalGeneralizer.level(for: visible, divisions: Self.heatDivisions, rawBelowMeters: 40)
            let newChip = SignalGeneralizer.level(for: visible, divisions: Self.chipDivisions, rawBelowMeters: 70)

            if dataChanged || newHeat != heatLevel {
                heatLevel = newHeat
                updateHeatmap(on: map, circles: mode.showsCircles ? generalized(circles, at: newHeat) : [])
            }
            if dataChanged || newChip != chipLevel {
                chipLevel = newChip
                updateScoreLabels(on: map, circles: mode.showsNumbers ? generalized(circles, at: newChip) : [])
            }
        }

        private func generalized(_ circles: [SignalCircle], at level: SignalGeneralizer.Level) -> [SignalCircle] {
            if let cached = generalizedCache[level] { return cached }
            let result = SignalGeneralizer.generalize(circles, at: level)
            generalizedCache[level] = result
            return result
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            applyGeneralization(on: mapView)
        }

        func updateHeatmap(on map: MKMapView, circles: [SignalCircle]) {
            if let heatmap {
                map.removeOverlay(heatmap)
                self.heatmap = nil
            }
            guard !circles.isEmpty else { return }

            let overlay = SignalHeatmapOverlay(circles: circles)
            // Below roads/labels, under the route line.
            map.insertOverlay(overlay, at: 0, level: .aboveRoads)
            heatmap = overlay
        }

        func updateScoreLabels(on map: MKMapView, circles: [SignalCircle]) {
            var wanted: [SpeedLabelKey: SignalCircle] = [:]
            for circle in circles {
                wanted[SpeedLabelKey(circle)] = circle
            }

            let staleKeys = scoreLabels.keys.filter { wanted[$0] == nil }
            let stale = staleKeys.compactMap { scoreLabels.removeValue(forKey: $0) }
            map.removeAnnotations(stale)

            var added: [SpeedLabelAnnotation] = []
            for (key, circle) in wanted where scoreLabels[key] == nil {
                let annotation = SpeedLabelAnnotation(coordinate: circle.coordinate, score: circle.score)
                scoreLabels[key] = annotation
                added.append(annotation)
            }

            pendingPopIn = added.count <= Self.popInLimit
                ? Set(added.map(ObjectIdentifier.init))
                : []
            map.addAnnotations(added)
        }

        func updateOutages(on map: MKMapView, reports: [OutageReport]) {
            map.removeAnnotations(outageAnnotations)
            outageAnnotations = reports.map(OutageReportAnnotation.init)
            map.addAnnotations(outageAnnotations)
        }

        fileprivate func updateRoute(on map: MKMapView, route: RouteState, circles: [SignalCircle]) {
            map.removeAnnotations(routeAnnotations)
            map.removeOverlays(routeOverlays)
            routeAnnotations = []
            routeOverlays = []

            if let start = route.start {
                routeAnnotations.append(RoutePointAnnotation(coordinate: start, isStart: true))
            }
            if let end = route.end {
                routeAnnotations.append(RoutePointAnnotation(coordinate: end, isStart: false))
            }
            map.addAnnotations(routeAnnotations)

            for (index, alternate) in route.alternates.enumerated() where alternate.count > 1 {
                let line = AlternateRoutePolyline(coordinates: alternate, count: alternate.count)
                line.index = index
                routeOverlays.append(line)
            }

            if route.coordinates.count > 1 {
                // Two passes: a wide soft glow under a signal-coloured core.
                routeOverlays += [
                    RouteGlowPolyline(coordinates: route.coordinates, count: route.coordinates.count),
                    SignalRoutePolyline.make(coordinates: route.coordinates, circles: circles)
                ]
            }
            map.addOverlays(routeOverlays, level: .aboveLabels)
        }

        fileprivate func frameRoutes(on map: MKMapView, route: RouteState, insets: UIEdgeInsets) {
            let lines = ([route.coordinates] + route.alternates).filter { $0.count > 1 }
            guard !lines.isEmpty else { return }

            let rect = lines.reduce(MKMapRect.null) { rect, line in
                rect.union(MKPolyline(coordinates: line, count: line.count).boundingMapRect)
            }

            // A tall sheet can leave almost no map; framing into a sliver
            // zooms out to the whole region. Keep at least ~35% of the map
            // for the routes and let the sheet overlap the rest.
            var target = insets
            let height = map.bounds.height
            if height > 0 {
                let minimumVisible = height * 0.35
                target.bottom = min(target.bottom, max(40, height - target.top - minimumVisible))
            }

            // MapKit adds edge padding on top of the layout margins, which
            // already hold the bottom chrome inset, so pass only the rest.
            let margins = map.layoutMargins
            let padding = UIEdgeInsets(
                top: max(0, target.top - margins.top),
                left: max(0, target.left - margins.left),
                bottom: max(0, target.bottom - margins.bottom),
                right: max(0, target.right - margins.right)
            )
            map.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

        /// Index of the alternate route under `point`, within a finger's width.
        private func alternateRoute(at point: CGPoint, in map: MKMapView) -> Int? {
            let tolerance: CGFloat = 22
            var best: (index: Int, distance: CGFloat)?

            for case let line as AlternateRoutePolyline in routeOverlays {
                let step = max(1, line.pointCount / 300)
                let points = line.points()
                var previous: CGPoint?

                for i in stride(from: 0, to: line.pointCount, by: step) {
                    let current = map.convert(points[i].coordinate, toPointTo: map)
                    if let previous {
                        let d = Self.distance(from: point, toSegment: previous, current)
                        if d < tolerance, best == nil || d < best!.distance {
                            best = (line.index, d)
                        }
                    }
                    previous = current
                }
            }
            return best?.index
        }

        private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !hasCenteredOnce, let userCoord = userLocation.location?.coordinate else { return }
            hasCenteredOnce = true
            let region = MKCoordinateRegion(
                center: userCoord,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            mapView.setRegion(region, animated: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)

            if let onMapTap = parent.onMapTap {
                onMapTap(coordinate)
                return
            }

            if let onSelect = parent.onSelectAlternateRoute, let index = alternateRoute(at: point, in: map) {
                onSelect(index)
                return
            }

            guard parent.allowsRoutePointSelection else { return }

            if parent.startPoint == nil {
                parent.startPoint = coordinate
            } else if parent.endPoint == nil {
                parent.endPoint = coordinate
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let speedAnnotation = annotation as? SpeedLabelAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: SignalScoreAnnotationView.reuseIdentifier,
                    for: annotation
                ) as! SignalScoreAnnotationView

                view.configure(score: speedAnnotation.score)
                view.canShowCallout = false
                if pendingPopIn.remove(ObjectIdentifier(speedAnnotation)) != nil {
                    view.popIn(delay: Double.random(in: 0...0.18))
                }
                return view
            }

            if annotation is OutageReportAnnotation {
                let identifier = "outageReport"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
                view.markerTintColor = .systemOrange
                view.canShowCallout = true
                view.displayPriority = .required
                return view
            }

            let identifier = "routePoint"
            let pinView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            pinView.annotation = annotation
            let isStart = (annotation as? RoutePointAnnotation)?.isStart ?? (annotation.title == "Start")
            pinView.markerTintColor = isStart
                ? UIColor(red: 0.09, green: 0.78, blue: 0.48, alpha: 1)
                : UIColor(red: 1.00, green: 0.60, blue: 0.30, alpha: 1)
            pinView.glyphImage = UIImage(systemName: isStart ? "location.fill" : "flag.checkered")
            pinView.canShowCallout = true
            pinView.displayPriority = .required
            return pinView
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is SignalHeatmapOverlay {
                return SignalHeatmapRenderer(overlay: overlay)
            }

            if let alternate = overlay as? AlternateRoutePolyline {
                let renderer = MKPolylineRenderer(polyline: alternate)
                renderer.strokeColor = UIColor(white: 0.72, alpha: 0.55)
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            // Checked before MKPolyline: the glow pass is a subclass of it.
            if let glowLine = overlay as? RouteGlowPolyline {
                let renderer = MKPolylineRenderer(polyline: glowLine)
                renderer.strokeColor = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.26)
                renderer.lineWidth = 14
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let signalLine = overlay as? SignalRoutePolyline {
                let renderer = MKGradientPolylineRenderer(polyline: signalLine)
                renderer.setColors(signalLine.stopColors, locations: signalLine.stopLocations)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.64, green: 0.90, blue: 1.00, alpha: 0.95)
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
