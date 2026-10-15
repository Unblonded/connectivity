//
//  ConnectivityMapView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import SwiftUI
import MapKit

struct SignalCircle: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let score: Int   // 0...100, from speedScore
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

fileprivate struct MapCoordinateState: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

fileprivate struct MapCircleState: Equatable {
    let coordinate: MapCoordinateState
    let radius: CLLocationDistance
    let score: Int
}

fileprivate struct MapOutageState: Equatable {
    let id: Int
    let coordinate: MapCoordinateState
    let message: String
}

fileprivate struct MapRenderState: Equatable {
    let circles: [MapCircleState]
    let displayMode: String
    let showsRouteBuilderOverlays: Bool
    let startPoint: MapCoordinateState?
    let endPoint: MapCoordinateState?
    let routeCoordinates: [MapCoordinateState]
    let outageReports: [MapOutageState]
}

final class SpeedLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let score: Int

    init(coordinate: CLLocationCoordinate2D, score: Int) {
        self.coordinate = coordinate
        self.score = score
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

/// Wide, translucent pass drawn under the route's core line.
final class RouteGlowPolyline: MKPolyline {}

/// Score bubble drawn on the map as a real blurred-glass chip, so the map
/// overlays match the Liquid Glass chrome in the rest of the app.
final class SignalScoreAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "signalScore"

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let scoreLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        centerOffset = .zero
        backgroundColor = .clear

        blurView.frame = bounds
        blurView.layer.cornerRadius = bounds.width / 2
        blurView.layer.cornerCurve = .continuous
        blurView.layer.borderWidth = 1.5
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        scoreLabel.frame = bounds
        scoreLabel.textAlignment = .center
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        scoreLabel.textColor = .white
        addSubview(scoreLabel)

        // Shadow is clipped to the circle; without an explicit path UIKit casts
        // it from the square layer and leaves a dark halo on the map.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(score: Int) {
        let color = uiColorForScore(score)
        scoreLabel.text = "\(score)"
        blurView.layer.borderColor = color.withAlphaComponent(0.95).cgColor
        blurView.contentView.backgroundColor = color.withAlphaComponent(0.30)
    }
}

struct ConnectivityMapView: UIViewRepresentable {
    @Binding var startPoint: CLLocationCoordinate2D?
    @Binding var endPoint: CLLocationCoordinate2D?
    @Binding var circles: [SignalCircle]
    var routeCoordinates: [CLLocationCoordinate2D]
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
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        let margins = UIEdgeInsets(top: 0, left: 0, bottom: bottomChromeInset, right: 0)
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

        let renderState = MapRenderState(
            circles: circles.map {
                MapCircleState(
                    coordinate: MapCoordinateState($0.coordinate),
                    radius: $0.radius,
                    score: $0.score
                )
            },
            displayMode: dataDisplayMode.rawValue,
            showsRouteBuilderOverlays: showsRouteBuilderOverlays,
            startPoint: startPoint.map(MapCoordinateState.init),
            endPoint: endPoint.map(MapCoordinateState.init),
            routeCoordinates: routeCoordinates.map(MapCoordinateState.init),
            outageReports: outageReports.map {
                MapOutageState(
                    id: $0.id,
                    coordinate: MapCoordinateState($0.coordinate),
                    message: $0.message
                )
            }
        )

        guard context.coordinator.lastRenderState != renderState else { return }
        context.coordinator.lastRenderState = renderState
        
        let customAnnotations = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(customAnnotations)
        map.removeOverlays(map.overlays)

        for circle in circles {
            if dataDisplayMode.showsCircles {
                ConnectivityMapView.drawSignalCircle(
                    on: map,
                    at: circle.coordinate,
                    radius: circle.radius,
                    score: circle.score
                )
            }

            if dataDisplayMode.showsNumbers {
                ConnectivityMapView.drawSignalNumber(
                    on: map,
                    at: circle.coordinate,
                    score: circle.score
                )
            }
        }

        for report in outageReports {
            map.addAnnotation(OutageReportAnnotation(report: report))
        }

        if showsRouteBuilderOverlays, let start = startPoint {
            let ann = MKPointAnnotation()
            ann.coordinate = start
            ann.title = "Start"
            map.addAnnotation(ann)
        }
        if showsRouteBuilderOverlays, let end = endPoint {
            let ann = MKPointAnnotation()
            ann.coordinate = end
            ann.title = "End"
            map.addAnnotation(ann)
        }
        if showsRouteBuilderOverlays, routeCoordinates.count > 1 {
            // Drawn in two passes: a wide soft glow underneath a bright core line.
            let glow = RouteGlowPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            let core = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            map.addOverlay(glow)
            map.addOverlay(core)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class SignalHeatOverlay: MKCircle {
        var score: Int = 0
        
        convenience init(center: CLLocationCoordinate2D, radius: CLLocationDistance, score: Int) {
            self.init(center: center, radius: radius)
            self.score = score
        }
    }

    @discardableResult
    static func drawSignalCircle(
        on map: MKMapView,
        at location: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        score: Int) -> SignalHeatOverlay {
        let circle = SignalHeatOverlay(center: location, radius: radius, score: score)
        map.addOverlay(circle)
        return circle
    }

    static func drawSignalNumber(
        on map: MKMapView,
        at location: CLLocationCoordinate2D,
        score: Int) {
        map.addAnnotation(SpeedLabelAnnotation(coordinate: location, score: score))
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ConnectivityMapView
        fileprivate var lastRenderState: MapRenderState?
        private var hasCenteredOnce = false

        init(_ parent: ConnectivityMapView) { self.parent = parent }

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
                let identifier = SignalScoreAnnotationView.reuseIdentifier
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? SignalScoreAnnotationView
                    ?? SignalScoreAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.configure(score: speedAnnotation.score)
                view.canShowCallout = false
                view.displayPriority = .required
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
            let isStart = annotation.title == "Start"
            pinView.markerTintColor = isStart
                ? UIColor(red: 0.09, green: 0.78, blue: 0.48, alpha: 1)
                : UIColor(red: 1.00, green: 0.60, blue: 0.30, alpha: 1)
            pinView.glyphImage = UIImage(systemName: isStart ? "location.fill" : "flag.checkered")
            pinView.canShowCallout = true
            pinView.displayPriority = .required
            return pinView
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circleOverlay = overlay as? SignalHeatOverlay {
                let renderer = MKCircleRenderer(circle: circleOverlay)
                let base = uiColorForScore(circleOverlay.score)

                renderer.fillColor = base.withAlphaComponent(0.28)
                renderer.strokeColor = base.withAlphaComponent(0.75)
                renderer.lineWidth = 1.2
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
