//
//  DesignSystem.swift
//  connectivity
//
//  Shared Liquid Glass building blocks used across the app.
//
import SwiftUI

// MARK: - Background

/// Slow-drifting light blooms over the base canvas.
///
/// This exists to give the Liquid Glass surfaces something to refract — glass
/// on a flat fill reads as a plain translucent rectangle.
struct AuroraBackground: View {
    var animated: Bool = true

    @State private var drift: CGFloat = 0

    init(animated: Bool = true) {
        self.animated = animated
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [AppTheme.bgDeep, AppTheme.bg, AppTheme.bgDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )

                bloom(AppTheme.aurora1, diameter: width * 1.15)
                    .offset(x: -width * 0.30, y: -height * 0.28 + drift * 26)

                bloom(AppTheme.aurora2, diameter: width * 0.95)
                    .offset(x: width * 0.34 - drift * 18, y: -height * 0.02)

                bloom(AppTheme.aurora3, diameter: width * 0.85)
                    .offset(x: -width * 0.12 + drift * 20, y: height * 0.33)
            }
            .compositingGroup()
        }
        .ignoresSafeArea()
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = 1
            }
        }
    }

    private func bloom(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.55), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 48)
            .blendMode(.plusLighter)
    }
}

// MARK: - Score ring

/// Circular signal gauge. Animates between values so live readings glide.
struct ScoreRing: View {
    let score: Int
    var diameter: CGFloat = 46
    var lineWidth: CGFloat = 4.5
    var showsScore: Bool = true
    /// Spins a scanning sweep around the ring while a measurement runs.
    var isActive: Bool = false

    private var fraction: Double {
        max(0, min(1, Double(score) / 100))
    }

    private var color: Color {
        colorForScore(score)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.55), color, color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 5)

            if isActive {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(
                            AngularGradient(
                                colors: [AppTheme.accent.opacity(0), AppTheme.accent],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(80)
                            ),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
                        .padding(-lineWidth * 1.6)
                        .shadow(color: AppTheme.accent.opacity(0.8), radius: 4)
                }
                .transition(.opacity)
            }

            if showsScore {
                Text("\(score)")
                    .font(.dsMono(diameter * 0.34, .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.55), value: fraction)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

// MARK: - Sparkline

/// Score history as a smooth line whose colour follows the signal scale, with a
/// soft fill underneath and a glowing dot on the latest reading.
struct ScoreSparkline: View {
    let scores: [Int]
    var lineWidth: CGFloat = 2.2

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = plotPoints(in: size)

            if points.count < 2 {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                    Text("Collecting readings…")
                }
                .font(.ds(11, .semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let line = smoothPath(through: points)
                let latest = points[points.count - 1]

                ZStack(alignment: .topLeading) {
                    // Midline at a score of 50.
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    }
                    .stroke(AppTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                    fillPath(from: line, points: points, height: size.height)
                        .fill(
                            LinearGradient(
                                colors: [colorForScore(scores.last ?? 0).opacity(0.32), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    line
                        .stroke(
                            verticalSignalGradient,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: colorForScore(scores.last ?? 0).opacity(0.6), radius: 4)

                    Circle()
                        .fill(colorForScore(scores.last ?? 0))
                        .frame(width: 7, height: 7)
                        .shadow(color: colorForScore(scores.last ?? 0), radius: 5)
                        .position(latest)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: scores)
    }

    /// Top of the chart is 100 (green), bottom is 0 (red), so the line picks up
    /// the colour of whatever score it is passing through.
    private var verticalSignalGradient: LinearGradient {
        LinearGradient(
            colors: [AppTheme.good, AppTheme.warn, AppTheme.bad],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func plotPoints(in size: CGSize) -> [CGPoint] {
        guard scores.count > 1 else { return [] }
        let inset: CGFloat = 4
        let height = size.height - inset * 2
        let step = size.width / CGFloat(scores.count - 1)

        return scores.enumerated().map { index, score in
            let clamped = CGFloat(max(0, min(100, score)))
            return CGPoint(x: CGFloat(index) * step, y: inset + height * (1 - clamped / 100))
        }
    }

    private func smoothPath(through points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midX = (previous.x + current.x) / 2
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: midX, y: previous.y),
                    control2: CGPoint(x: midX, y: current.y)
                )
            }
        }
    }

    private func fillPath(from line: Path, points: [CGPoint], height: CGFloat) -> Path {
        var path = line
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
        path.addLine(to: CGPoint(x: points[0].x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Radar pulse

/// Concentric rings that expand and fade from the centre, like a signal
/// broadcasting. Sits behind an icon.
struct RadarPulse: View {
    var color: Color = AppTheme.accent
    var rings: Int = 3
    var period: Double = 2.8

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(0..<rings, id: \.self) { ring in
                    let phase = ((t / period) + Double(ring) / Double(rings))
                        .truncatingRemainder(dividingBy: 1)

                    Circle()
                        .strokeBorder(color.opacity(0.55 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(0.45 + phase * 0.95)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Circular glass icon button — the app's primary chrome control.
struct GlassIconButton: View {
    let systemName: String
    var diameter: CGFloat = 42
    var tint: Color = AppTheme.accent
    var glassTint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.40, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(glassTint).interactive(), in: Circle())
    }
}

/// Adds a subtle press-down response to custom glass controls.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Containers

/// Rounded glass panel with an optional titled header.
struct GlassCard<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    private let cornerRadius: CGFloat
    private let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        cornerRadius: CGFloat = 26,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(title.uppercased())
                        .font(.ds(11, .bold))
                        .tracking(1.1)
                        .foregroundStyle(AppTheme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 11)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }
}

/// Hairline divider sized for use inside `GlassCard`.
struct GlassDivider: View {
    var inset: CGFloat = 18

    var body: some View {
        Rectangle()
            .fill(AppTheme.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Controls

/// Glass segmented control with a sliding selection capsule.
struct GlassSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    @Namespace private var indicator

    init(options: [(label: String, value: Value)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.value == selection

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.ds(13, isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.bgDeep : AppTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(AppTheme.accent)
                                    .matchedGeometryEffect(id: "segment", in: indicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(.clear, in: Capsule())
        .overlay {
            Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }
}

/// Label-and-value row that opens a menu of choices. Replaces `Picker` inside
/// glass cards, where the stock control's own background fights the material.
struct GlassMenuRow<Value: Hashable>: View {
    let title: String
    let systemImage: String?
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var isEnabled: Bool = true

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? "—"
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 11) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)
                }

                Text(title)
                    .font(.ds(15, .medium))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text(selectedLabel)
                    .font(.ds(14, .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.muted.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Toggle row styled to match `GlassMenuRow`.
struct GlassToggleRow: View {
    let title: String
    let systemImage: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20)
            }

            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.ds(15, .medium))
                    .foregroundStyle(.white)
            }
            .tint(AppTheme.accentDeep)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}

/// Explanatory footnote inside a glass card.
struct GlassNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AppTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .padding(.top, 2)
    }
}

/// Read-only key/value row.
struct GlassStatRow: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 11) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20)
            }

            Text(title)
                .font(.ds(15, .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Text(value)
                .font(.dsMono(14, .semibold))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

/// Full-width action row used for destructive and account actions.
struct GlassActionRow: View {
    let title: String
    let systemImage: String
    var tint: Color = AppTheme.accent
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)

                Text(title)
                    .font(.ds(15, .semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView().controlSize(.small).tint(tint)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled && !isBusy ? 1 : 0.45)
    }
}

// MARK: - Text input

/// Glass text field with a leading icon, used by auth and the route planner.
struct GlassField<Field: View>: View {
    let systemImage: String
    var tint: Color = AppTheme.accent
    @ViewBuilder let field: () -> Field

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            field()
                .font(.ds(15, .medium))
                .foregroundStyle(.white)
                .tint(AppTheme.accent)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Misc

/// Small pill used for inline status, counts and labels.
struct GlassBadge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = AppTheme.accent

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.ds(11, .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

/// Horizontal red -> orange -> green scale with labelled ends.
struct SignalScaleBar: View {
    var height: CGFloat = 10

    var body: some View {
        VStack(spacing: 7) {
            Capsule()
                .fill(AppTheme.signalGradient)
                .frame(height: height)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }

            HStack {
                Text("0")
                Spacer()
                Text("50")
                Spacer()
                Text("100")
            }
            .font(.dsMono(10, .semibold))
            .foregroundStyle(AppTheme.muted)
        }
    }
}
