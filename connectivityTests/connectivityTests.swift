//
//  connectivityTests.swift
//  connectivityTests
//
//  Created by Edmund Edjhuryan on 9/9/26.
//

import Testing
import MapKit
@testable import connectivity

struct connectivityTests {

    /// 5,000 points scattered over roughly 10 km around Los Angeles.
    private func sampleCircles(count: Int = 5_000) -> [SignalCircle] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            SignalCircle(
                coordinate: CLLocationCoordinate2D(
                    latitude: 34.05 + Double.random(in: -0.05...0.05, using: &generator),
                    longitude: -118.24 + Double.random(in: -0.05...0.05, using: &generator)
                ),
                radius: 90,
                score: Int.random(in: 0...100, using: &generator)
            )
        }
    }

    /// A visible rect `spanDegrees` wide centred on the sample area.
    private func visibleRect(spanDegrees: Double) -> MKMapRect {
        let center = CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: center.latitude + spanDegrees / 2, longitude: center.longitude - spanDegrees / 2))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: center.latitude - spanDegrees / 2, longitude: center.longitude + spanDegrees / 2))
        return MKMapRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    @Test func zoomingOutMergesPoints() {
        let circles = sampleCircles()

        let close = SignalGeneralizer.level(for: visibleRect(spanDegrees: 0.005), divisions: 28, rawBelowMeters: 40)
        // Chip density: 7–14 cells across the screen, whatever the data size.
        let city = SignalGeneralizer.level(for: visibleRect(spanDegrees: 0.1), divisions: 7, rawBelowMeters: 70)
        let region = SignalGeneralizer.level(for: visibleRect(spanDegrees: 1.0), divisions: 28, rawBelowMeters: 40)

        #expect(close.cellSize == 0, "Street level should show raw data")
        #expect(SignalGeneralizer.generalize(circles, at: close).count == circles.count)

        let cityCount = SignalGeneralizer.generalize(circles, at: city).count
        let regionCount = SignalGeneralizer.generalize(circles, at: region).count

        // ~9 km x 11 km of data in cells of at least 0.65 km.
        #expect(cityCount <= 300)
        #expect(regionCount < cityCount)
        #expect(regionCount <= 60)
    }

    @Test func clusterScoreIsMeanOfMembers() {
        let base = CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)
        let circles = [10, 50, 90].map {
            SignalCircle(coordinate: base, radius: 50, score: $0)
        }
        // A cell far larger than the points' spread puts them in one bucket.
        let merged = SignalGeneralizer.generalize(circles, at: .init(cellSize: 1_000_000))

        #expect(merged.count == 1)
        #expect(merged.first?.score == 50)
        #expect(merged.first?.radius == 50)
    }

    @Test func gridIsStableWhilePanning() {
        // Same zoom, shifted view: the cell size must not change, otherwise
        // clusters would reshuffle on every pan.
        let rect = visibleRect(spanDegrees: 0.1)
        let shifted = rect.offsetBy(dx: rect.width * 0.37, dy: rect.height * 0.21)

        let a = SignalGeneralizer.level(for: rect, divisions: 7, rawBelowMeters: 70)
        let b = SignalGeneralizer.level(for: shifted, divisions: 7, rawBelowMeters: 70)
        #expect(a == b)
    }
}

struct routePlannerTests {

    /// A straight north-south line of `count` points.
    private func line(from start: CLLocationCoordinate2D, latStep: Double, lonOffset: (Int) -> Double = { _ in 0 }, count: Int = 100) -> [CLLocationCoordinate2D] {
        (0..<count).map {
            CLLocationCoordinate2D(latitude: start.latitude + Double($0) * latStep, longitude: start.longitude + lonOffset($0))
        }
    }

    private let origin = CLLocationCoordinate2D(latitude: 34.0, longitude: -118.2)

    @Test func identicalRouteNeedsNoViaPoints() {
        let fastest = line(from: origin, latStep: 0.001)
        #expect(RoutePlanner.viaPoints(for: fastest, against: fastest).isEmpty)
    }

    @Test func detourIsPinnedAtItsWidestPoint() {
        let fastest = line(from: origin, latStep: 0.001)
        // Bulges ~1.8 km east in the middle, then rejoins.
        let detour = line(from: origin, latStep: 0.001, lonOffset: { i in
            (30...70).contains(i) ? 0.02 * sin(Double(i - 30) / 40 * .pi) : 0
        })

        let via = RoutePlanner.viaPoints(for: detour, against: fastest)
        #expect(via.count == 1)
        // Peak of the bulge is at index 50.
        #expect(abs(via[0].latitude - detour[50].latitude) < 0.002)
        #expect(via[0].longitude > origin.longitude + 0.015)
    }

    @Test func parallelStreetIsStillPinned() {
        let fastest = line(from: origin, latStep: 0.001)
        // A frontage road ~110 m east of the freeway for the middle stretch.
        let parallel = line(from: origin, latStep: 0.001, lonOffset: { i in
            (30...70).contains(i) ? 0.0012 : 0
        })

        let via = RoutePlanner.viaPoints(for: parallel, against: fastest)
        #expect(via.count == 1)
        #expect(via[0].longitude > origin.longitude + 0.001)
    }

    @Test func viaPointsComeOutInDrivingOrder() {
        let fastest = line(from: origin, latStep: 0.001)
        // Two separate bulges: a small one first, a larger one later.
        let detour = line(from: origin, latStep: 0.001, lonOffset: { i in
            if (10...30).contains(i) { return 0.008 * sin(Double(i - 10) / 20 * .pi) }
            if (60...90).contains(i) { return 0.02 * sin(Double(i - 60) / 30 * .pi) }
            return 0
        })

        let via = RoutePlanner.viaPoints(for: detour, against: fastest)
        #expect(via.count == 2)
        #expect(via[0].latitude < via[1].latitude)
    }

    @Test func outAndBackDetourIsDetected() {
        // East 3 km, back along the same road, then south.
        let east = (0...30).map { CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude + Double($0) * 0.001) }
        let back = east.reversed().dropFirst()
        let south = (1...40).map { CLLocationCoordinate2D(latitude: origin.latitude - Double($0) * 0.001, longitude: origin.longitude) }

        #expect(RoutePlanner.doublesBack(east + back + south))
    }

    @Test func ordinaryRoutesDoNotDoubleBack() {
        let straight = line(from: origin, latStep: 0.001)
        // An L-shaped route: north then east, never revisiting.
        let corner = line(from: origin, latStep: 0.001, count: 50)
            + (1...50).map { CLLocationCoordinate2D(latitude: origin.latitude + 0.049, longitude: origin.longitude + Double($0) * 0.001) }

        #expect(!RoutePlanner.doublesBack(straight))
        #expect(!RoutePlanner.doublesBack(corner))
    }

    @Test func appleMapsURLCarriesWaypointsInOrder() throws {
        let end = CLLocationCoordinate2D(latitude: 34.1, longitude: -118.3)
        let via = [
            CLLocationCoordinate2D(latitude: 34.03, longitude: -118.21),
            CLLocationCoordinate2D(latitude: 34.06, longitude: -118.25)
        ]
        let url = try #require(RoutePlanner.navigationURL(app: .appleMaps, start: nil, end: end, viaPoints: via))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.host == "maps.apple.com")
        #expect(url.path == "/directions")
        #expect(!items.contains { $0.name == "source" }, "No source means current location")
        #expect(items.filter { $0.name == "waypoint" }.map(\.value) == ["34.030000,-118.210000", "34.060000,-118.250000"])
        #expect(items.first { $0.name == "mode" }?.value == "driving")
    }

    @Test func googleMapsURLJoinsWaypoints() throws {
        let url = try #require(RoutePlanner.navigationURL(
            app: .googleMaps,
            start: origin,
            end: CLLocationCoordinate2D(latitude: 34.1, longitude: -118.3),
            viaPoints: [CLLocationCoordinate2D(latitude: 34.05, longitude: -118.22)]
        ))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.first { $0.name == "origin" }?.value == "34.000000,-118.200000")
        #expect(items.first { $0.name == "waypoints" }?.value == "34.050000,-118.220000")
        #expect(items.first { $0.name == "travelmode" }?.value == "driving")
    }
}
