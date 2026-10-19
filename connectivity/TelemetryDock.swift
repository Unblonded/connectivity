//
//  TelemetryDock.swift
//  connectivity
//
//  Bottom readout on the map. Collapsed it is a single glass bar with the live
//  score and street; tapped, it grows into a telemetry panel.
//
import SwiftUI

/// Signal data around the user, summarised by `ContentView` from map circles.
struct NearbySignalSummary: Equatable {
    let averageScore: Int
    let spotCount: Int
    let radiusMeters: Double
}

struct TelemetryDock: View {
    let isOnWiFi: Bool
    let fallbackScore: Int
    let addressLine: String
    let carrier: String
    let viewOnlyMode: Bool
    let nearby: NearbySignalSummary?
    let onRunTest: () -> Void

    @State private var isExpanded = false

    private var telemetry: LiveTelemetry { .shared }

    private var score: Int {
        telemetry.latestScore ?? fallbackScore
    }

    private var canRunTest: Bool {
        !viewOnlyMode && !isOnWiFi && !telemetry.phase.isMeasuring
    }

    private var cornerRadius: CGFloat {
        isExpanded ? 30 : 34
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                expandedPanel
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)).animation(.smooth(duration: 0.32).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), AppTheme.hairline, colorForScore(score).opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }

    // MARK: Header

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                gauge

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isOnWiFi ? "Wi-Fi connected" : scoreDescriptor(score))
                            .font(.ds(15, .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.interpolate)

                        if telemetry.phase.isMeasuring {
                            phaseChip
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }

                    Text(addressLine)
                        .font(.dsMono(11, .medium))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    if !carrier.isEmpty {
                        Text(carrier)
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
                    } else {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.muted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: telemetry.phase)
        .accessibilityLabel("Live signal: \(isOnWiFi ? "Wi-Fi" : "\(score), \(scoreDescriptor(score))")")
        .accessibilityHint(isExpanded ? "Collapse telemetry" : "Expand telemetry")
    }

    @ViewBuilder
    private var gauge: some View {
        if isOnWiFi {
            Image(systemName: "wifi")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 46, height: 46)
                .background(AppTheme.accent.opacity(0.14), in: Circle())
                .overlay {
                    Circle().strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1)
                }
        } else {
            ScoreRing(score: score, diameter: 46, isActive: telemetry.phase.isMeasuring)
        }
    }

    private var phaseChip: some View {
        HStack(spacing: 3) {
            Image(systemName: telemetry.phase == .download ? "arrow.down" : "arrow.up")
                .font(.system(size: 8, weight: .heavy))
            Text("TESTING")
                .font(.ds(8, .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(AppTheme.accent.opacity(0.16), in: Capsule())
        .symbolEffect(.pulse, options: .repeating)
    }

    // MARK: Expanded

    private var expandedPanel: some View {
        VStack(spacing: 14) {
            GlassDivider(inset: 0)

            HStack(spacing: 10) {
                metricTile(
                    title: "Download",
                    systemImage: "arrow.down.circle.fill",
                    value: telemetry.downloadMbps,
                    isLive: telemetry.phase == .download
                )
                metricTile(
                    title: "Upload",
                    systemImage: "arrow.up.circle.fill",
                    value: telemetry.uploadMbps,
                    isLive: telemetry.phase == .upload
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SESSION")
                        .font(.ds(10, .bold))
                        .tracking(1.0)
                        .foregroundStyle(AppTheme.muted)

                    Spacer()

                    if let average = telemetry.averageScore {
                        Text("avg \(average) · \(telemetry.history.count) readings")
                            .font(.dsMono(10, .semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                ScoreSparkline(scores: telemetry.history.map(\.score))
                    .frame(height: 52)
            }

            HStack(spacing: 8) {
                infoChip(systemImage: "scope", text: nearbyText, tint: nearby.map { colorForScore($0.averageScore) } ?? AppTheme.muted)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    infoChip(systemImage: "clock", text: lastTestText(now: context.date), tint: AppTheme.muted)
                }
            }

            Button(action: onRunTest) {
                HStack(spacing: 8) {
                    if telemetry.phase.isMeasuring {
                        ProgressView().tint(AppTheme.bgDeep)
                        Text(telemetry.phase.label + "…")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(testButtonTitle)
                    }
                }
                .font(.ds(15, .bold))
                .foregroundStyle(AppTheme.bgDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.accent)
            .disabled(!canRunTest)
            .opacity(canRunTest || telemetry.phase.isMeasuring ? 1 : 0.5)
            .sensoryFeedback(.success, trigger: telemetry.completedTests) { _, _ in isExpanded }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var testButtonTitle: String {
        if viewOnlyMode { return "Testing off in view-only mode" }
        if isOnWiFi { return "Switch to cellular to test" }
        return "Test now"
    }

    private var nearbyText: String {
        guard let nearby else { return "No data nearby" }
        return "\(nearby.averageScore) avg · \(nearby.spotCount) spots"
    }

    private func lastTestText(now: Date) -> String {
        guard let lastTestDate = telemetry.lastTestDate else { return "No test yet" }
        let seconds = max(0, Int(now.timeIntervalSince(lastTestDate)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func metricTile(title: String, systemImage: String, value: Double?, isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLive)

                Text(title.uppercased())
                    .font(.ds(10, .bold))
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatMbps(value))
                    .font(.dsMono(24, .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("Mbps")
                    .font(.ds(11, .semibold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isLive ? AppTheme.accent.opacity(0.55) : AppTheme.hairline, lineWidth: 1)
        }
        .animation(.smooth(duration: 0.4), value: value)
    }

    private func infoChip(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.ds(11, .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay { Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1) }
    }

    private func formatMbps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}
