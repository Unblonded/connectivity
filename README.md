# Connectivity

An iOS app for crowdsourcing and visualizing internet connection quality — see dead zones, weak spots, and strong signal areas on a live map before you need them.

## What it does

- **Speed testing** — runs periodic download/upload tests in the background and scores connection quality (0–100) based on a weighted, logarithmic blend of both.
- **Live map** — plots tested locations as color-graded circles (red → orange → green) so you can spot low-signal areas at a glance.
- **Route builder** — tap two points on the map to preview a route between them.
- **Configurable testing** — adjust test frequency, download file size, and upload payload size to balance accuracy against data usage.
- **View-only mode** — browse the map without running tests or submitting your own data.
- **Auto + manual map refresh** — the map pulls new data on an interval (adjustable) or on demand via the refresh button.

## Project structure

connectivity/
├── connectivity/ # iOS app (SwiftUI)
│ ├── ContentView.swift # main screen: map, route builder, live stats
│ ├── ConnectivityMapView.swift # MapKit wrapper + overlay rendering
│ ├── ConnectivitySample.swift # scoring logic + color mapping
│ └── SettingsView.swift # user-configurable test settings
└── server/ # Node/Express backend
├── index.js # sample ingestion + grid-based aggregation
└── data/ # raw + calculated sample storage


## Backend

Simple Express API that collects raw speed samples, buckets them into a coarse lat/lon grid, and serves averaged results per grid cell.

- `POST /samples` — submit a `{ latitude, longitude, downloadMbps, uploadMbps }` reading (token-gated)
- `GET /samples` — raw samples
- `GET /calculated?since=<id>` — aggregated, grid-averaged results

## iOS app

Built with SwiftUI + MapKit. Requires Xcode and an Apple Developer account for device installs.

```bash
open connectivity.xcodeproj
```

Update the API base URL in `ContentView.swift` (`loadCircles()`) to point at your backend.

## Signal scoring

Score blends download (70%) and upload (30%) speed on a logarithmic curve, capped against configurable max reference speeds — so realistic "good" speeds reach the top of the scale rather than needing gigabit connections to register as excellent.
