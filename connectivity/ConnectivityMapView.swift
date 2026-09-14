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

struct SignalCircleJSON: Decodable {
    let id: Int
    let loc: Location
    let radius: Double
    let speed: Speed
    let sampleCount: Int

    struct Location: Decodable {
        let lat: Double
        let lon: Double
    }

    struct Speed: Decodable {
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

final class SpeedLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let score: Int

    init(coordinate: CLLocationCoordinate2D, score: Int) {
        self.coordinate = coordinate
        self.score = score
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

struct ConnectivityMapView: UIViewRepresentable {
    @Binding var startPoint: CLLocationCoordinate2D?
    @Binding var endPoint: CLLocationCoordinate2D?
    @Binding var circles: [SignalCircle]
    var routeCoordinates: [CLLocationCoordinate2D]
    @Binding var recenterMap: Bool

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if recenterMap {
            let coord = UserStore.shared.coordinate
            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            map.setRegion(region, animated: true)
            DispatchQueue.main.async { self.recenterMap = false }
        }
        
        let customAnnotations = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(customAnnotations)
        map.removeOverlays(map.overlays)

        for circle in circles {
            ConnectivityMapView.drawSignalCircle(on: map, at: circle.coordinate, radius: circle.radius, score: circle.score)
        }

        if let start = startPoint {
            let ann = MKPointAnnotation()
            ann.coordinate = start
            ann.title = "Start"
            map.addAnnotation(ann)
        }
        if let end = endPoint {
            let ann = MKPointAnnotation()
            ann.coordinate = end
            ann.title = "End"
            map.addAnnotation(ann)
        }
        if routeCoordinates.count > 1 {
            let line = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            map.addOverlay(line)
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
        map.addAnnotation(SpeedLabelAnnotation(coordinate: location, score: score))
        return circle
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ConnectivityMapView
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
                let identifier = "speedLabel"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.glyphText = "\(speedAnnotation.score)"
                view.markerTintColor = uiColorForScore(speedAnnotation.score)
                view.canShowCallout = false
                view.displayPriority = .required
                return view
            }

            let pinView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            pinView.markerTintColor = .systemRed
            pinView.canShowCallout = true
            return pinView
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circleOverlay = overlay as? SignalHeatOverlay {
                let renderer = MKCircleRenderer(circle: circleOverlay)
                let base = uiColorForScore(circleOverlay.score)

                renderer.fillColor = base.withAlphaComponent(0.25)
                renderer.strokeColor = base.withAlphaComponent(0.65)
                renderer.lineWidth = 1.5
                return renderer
            }
            
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.9)
                renderer.lineWidth = 4
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
