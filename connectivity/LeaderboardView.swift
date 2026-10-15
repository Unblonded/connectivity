//
//  LeaderboardView.swift
//  connectivity
//
//  Created by Codex on 9/21/26.
//
import SwiftUI

struct LeaderboardEntry: Decodable, Identifiable {
    let username: String
    let contributionCount: Int

    var id: String { username }
}

struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("userName") private var userName: String = ""

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let usersEndpoint = URL(string: "https://api.kalculator.lol/users")!

    private var podium: [LeaderboardEntry] { Array(entries.prefix(3)) }
    private var remainder: [LeaderboardEntry] { Array(entries.dropFirst(3)) }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                content
            }
            .foregroundStyle(.white)
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadLeaderboard()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(isLoading)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(AppTheme.accent)
        }
        .task {
            loadLeaderboardIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            loadingState
        } else if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    if !podium.isEmpty {
                        podiumCard
                    }

                    if !remainder.isEmpty {
                        GlassCard(title: "Everyone else", systemImage: "list.number") {
                            VStack(spacing: 0) {
                                ForEach(Array(remainder.enumerated()), id: \.element.id) { index, entry in
                                    LeaderboardRow(
                                        rank: index + 4,
                                        entry: entry,
                                        isCurrentUser: entry.username == userName
                                    )

                                    if index < remainder.count - 1 {
                                        GlassDivider(inset: 18)
                                    }
                                }
                            }
                            .padding(.bottom, 6)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                await loadLeaderboardAsync()
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)

            Text("Loading contributors…")
                .font(.ds(14, .medium))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(30)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: errorMessage == nil ? "person.3.sequence.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(errorMessage == nil ? AppTheme.accent : AppTheme.warn)

            Text(errorMessage ?? "No contributors yet")
                .font(.ds(16, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if errorMessage != nil {
                Button {
                    loadLeaderboard()
                } label: {
                    Text("Try again")
                        .font(.ds(15, .bold))
                        .foregroundStyle(AppTheme.bgDeep)
                        .frame(width: 150)
                        .frame(height: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.accent)
            }
        }
        .padding(26)
        .frame(maxWidth: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
        .padding(24)
    }

    /// Top three as bottom-aligned cards, with the leader raised and crowned.
    private var podiumCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(medalColor(1))

                Text("TOP CONTRIBUTORS")
                    .font(.ds(11, .bold))
                    .tracking(1.1)
                    .foregroundStyle(AppTheme.muted)

                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 9) {
                if podium.count > 1 {
                    podiumColumn(entry: podium[1], rank: 2)
                }

                podiumColumn(entry: podium[0], rank: 1)

                if podium.count > 2 {
                    podiumColumn(entry: podium[2], rank: 3)
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }

    private func podiumColumn(entry: LeaderboardEntry, rank: Int) -> some View {
        let color = medalColor(rank)
        let isLead = rank == 1
        let avatarSize: CGFloat = isLead ? 52 : 44

        return VStack(spacing: 7) {
            Image(systemName: isLead ? "crown.fill" : "rosette")
                .font(.system(size: isLead ? 13 : 11, weight: .bold))
                .foregroundStyle(color)

            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: avatarSize, height: avatarSize)
                    .blur(radius: 12)
                    .opacity(0.45)

                Text(initial(for: entry.username))
                    .font(.ds(isLead ? 20 : 17, .bold))
                    .foregroundStyle(color)
                    .frame(width: avatarSize, height: avatarSize)
                    .glassEffect(.regular, in: Circle())
                    .overlay {
                        Circle().strokeBorder(color.opacity(0.5), lineWidth: 1.5)
                    }
            }

            Text(entry.username)
                .font(.ds(12, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("\(entry.contributionCount)")
                .font(.dsMono(isLead ? 19 : 16, .bold))
                .foregroundStyle(color)

            Text(rankLabel(rank))
                .font(.ds(10, .bold))
                .foregroundStyle(AppTheme.bgDeep)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color, in: Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isLead ? 16 : 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        }
    }

    private func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 1: return "1ST"
        case 2: return "2ND"
        default: return "3RD"
        }
    }

    private func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.82, blue: 0.34)
        case 2: return Color(red: 0.80, green: 0.85, blue: 0.92)
        case 3: return Color(red: 0.89, green: 0.58, blue: 0.34)
        default: return AppTheme.accent
        }
    }

    private func initial(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(first).uppercased()
    }

    // MARK: - Loading

    private func loadLeaderboardIfNeeded() {
        guard entries.isEmpty else { return }
        loadLeaderboard()
    }

    private func loadLeaderboard() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        NetworkClient.shared.get(url: usersEndpoint, as: [LeaderboardEntry].self) { fetchedEntries, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error {
                    errorMessage = "Could not load contributors. \(error.localizedDescription)"
                    return
                }

                entries = Array((fetchedEntries ?? []).prefix(300))
            }
        }
    }

    private func loadLeaderboardAsync() async {
        await withCheckedContinuation { continuation in
            NetworkClient.shared.get(url: usersEndpoint, as: [LeaderboardEntry].self) { fetchedEntries, error in
                DispatchQueue.main.async {
                    if let error {
                        errorMessage = "Could not refresh contributors. \(error.localizedDescription)"
                    } else {
                        errorMessage = nil
                        entries = Array((fetchedEntries ?? []).prefix(300))
                    }

                    continuation.resume()
                }
            }
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.dsMono(13, .bold))
                .foregroundStyle(isCurrentUser ? AppTheme.accent : AppTheme.muted)
                .frame(width: 32, alignment: .trailing)

            HStack(spacing: 6) {
                Text(entry.username)
                    .font(.ds(15, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if isCurrentUser {
                    GlassBadge(text: "YOU")
                }
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.contributionCount)")
                    .font(.dsMono(15, .bold))
                    .foregroundStyle(AppTheme.accent)

                Text("pts")
                    .font(.ds(10, .semibold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background {
            if isCurrentUser {
                Rectangle().fill(AppTheme.accent.opacity(0.08))
            }
        }
    }
}

#Preview {
    LeaderboardView()
        .preferredColorScheme(.dark)
}
