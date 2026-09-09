//
//  ConnectivityMapView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import SwiftUI
import MapKit

struct ConnectivityMapView: UIViewRepresentable {
    @Binding var samples: [ConnectivitySample]
    @Binding var startPoint: CLLocationCoordinate2D?
    @Binding var endPoint: CLLocationCoordinate2D?
    var showSamples: Bool
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

        // Render filled heat/signal circles for each connectivity sample
        if showSamples {
            for sample in samples {
                // Add annotation marker
                let ann = SampleAnnotation(sample: sample)
                map.addAnnotation(ann)
                
                // Add filled radius circle around sample (e.g., 200 meter radius)
                let circle = SignalHeatOverlay(center: sample.coordinate, radius: 200, tier: sample.signalTier)
                map.addOverlay(circle)
            }
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

    // Custom MKCircle class to retain signal strength metadata
    final class SignalHeatOverlay: MKCircle {
        var tier: SignalTier = .good
        
        convenience init(center: CLLocationCoordinate2D, radius: CLLocationDistance, tier: SignalTier) {
            self.init(center: center, radius: radius)
            self.tier = tier
        }
    }

    final class SampleAnnotation: NSObject, MKAnnotation {
        let sample: ConnectivitySample
        var coordinate: CLLocationCoordinate2D { sample.coordinate }
        var title: String? { sample.name }
        init(sample: ConnectivitySample) { self.sample = sample }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ConnectivityMapView
        private var hasAddedNearbyHeatmap = false

        init(_ parent: ConnectivityMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !hasAddedNearbyHeatmap, let userCoord = userLocation.location?.coordinate else { return }
            hasAddedNearbyHeatmap = true
            
            // Example: Add a radius circle directly around the user (e.g. 300 meters)
            let userRadiusCircle = SignalHeatOverlay(
                center: userCoord,
                radius: 300,
                tier: .good
            )
            mapView.addOverlay(userRadiusCircle)
            
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
            } else {
                parent.startPoint = coordinate
                parent.endPoint = nil
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let sampleAnn = annotation as? SampleAnnotation {
                let view = MKMarkerAnnotationView(annotation: sampleAnn, reuseIdentifier: "sample")
                switch sampleAnn.sample.signalTier {
                case .good: view.markerTintColor = UIColor(red: 0.09, green: 0.78, blue: 0.48, alpha: 1)
                case .poor: view.markerTintColor = UIColor(red: 1.00, green: 0.60, blue: 0.30, alpha: 1)
                case .dead: view.markerTintColor = UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)
                }
                view.canShowCallout = true
                return view
            }
            
            let pinView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "nearbyPin")
            pinView.markerTintColor = .systemRed
            pinView.canShowCallout = true
            return pinView
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // 1. Handle Radius Circles (Heatmap Overlays)
            if let circleOverlay = overlay as? SignalHeatOverlay {
                let renderer = MKCircleRenderer(circle: circleOverlay)
                
                // Set fill and stroke colors based on signal tier with opacity
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
            
            // 2. Handle Route Lines
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
