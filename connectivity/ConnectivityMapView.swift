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
    let tier: SignalTier
}

struct ConnectivityMapView: UIViewRepresentable {
    @Binding var startPoint: CLLocationCoordinate2D?
    @Binding var endPoint: CLLocationCoordinate2D?
    @Binding var circles: [SignalCircle]
    var routeCoordinates: [CLLocationCoordinate2D]

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
        let customAnnotations = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(customAnnotations)
        map.removeOverlays(map.overlays)

        for circle in circles {
            ConnectivityMapView.drawSignalCircle(on: map, at: circle.coordinate, radius: circle.radius, tier: circle.tier)
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
        var tier: SignalTier = .good
        
        convenience init(center: CLLocationCoordinate2D, radius: CLLocationDistance, tier: SignalTier) {
            self.init(center: center, radius: radius)
            self.tier = tier
        }
    }

    @discardableResult
    static func drawSignalCircle(
        on map: MKMapView,
        at location: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        tier: SignalTier) -> SignalHeatOverlay {
        let circle = SignalHeatOverlay(center: location, radius: radius, tier: tier)
        map.addOverlay(circle)
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
            let pinView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            pinView.markerTintColor = .systemRed
            pinView.canShowCallout = true
            return pinView
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circleOverlay = overlay as? SignalHeatOverlay {
                let renderer = MKCircleRenderer(circle: circleOverlay)
                
                switch circleOverlay.tier {
                case .good:
                    renderer.fillColor = UIColor(red: 0.09, green: 0.78, blue: 0.48, alpha: 0.25)
                    renderer.strokeColor = UIColor(red: 0.09, green: 0.78, blue: 0.48, alpha: 0.60)
                case .poor:
                    renderer.fillColor = UIColor(red: 1.00, green: 0.60, blue: 0.30, alpha: 0.25)
                    renderer.strokeColor = UIColor(red: 1.00, green: 0.60, blue: 0.30, alpha: 0.60)
                case .dead:
                    renderer.fillColor = UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 0.30)
                    renderer.strokeColor = UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 0.70)
                }
                
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
