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

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let usersEndpoint = URL(string: "https://api.kalculator.lol/users")!

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()

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
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadLeaderboard()
                    } label: {
                        Image(systemName: "arrow.clockwise")
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
            ProgressView("Loading contributors...")
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.muted)
        } else if entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: errorMessage == nil ? "person.3.sequence.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text(errorMessage ?? "No contributors yet")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    loadLeaderboard()
                }
                .buttonStyle(.borderedProminent)
                .opacity(errorMessage == nil ? 0 : 1)
                .disabled(errorMessage == nil)
            }
            .padding(24)
        } else {
            List {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: index + 1, entry: entry)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                } header: {
                    Text("Top 300 Contributors")
                        .foregroundStyle(AppTheme.muted)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await loadLeaderboardAsync()
            }
        }
    }

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

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(rankColor)
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.username)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("\(entry.contributionCount) contributions")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer(minLength: 8)

            Image(systemName: "cellularbars")
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 6)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.82, blue: 0.34)
        case 2: return Color(red: 0.78, green: 0.82, blue: 0.88)
        case 3: return Color(red: 0.86, green: 0.55, blue: 0.32)
        default: return AppTheme.accent
        }
    }
}

#Preview {
    LeaderboardView()
        .preferredColorScheme(.dark)
}
