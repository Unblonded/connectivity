//
//  SettingsView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/10/26.
//
import SwiftUI

enum DownloadTestSize: String, CaseIterable, Identifiable {
    case mb10 = "10mb.bin"
    case mb100 = "100mb.bin"
    case mb500 = "500mb.bin"
    case gb1 = "1000mb.bin"
    case mb10000 = "10000mb.bin"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mb10: return "10 MB"
        case .mb100: return "100 MB"
        case .mb500: return "500 MB"
        case .gb1: return "1 GB"
        case .mb10000: return "10 GB"
        }
    }

    var url: URL {
        URL(string: "https://ftp.bit.nl/speedtest/\(rawValue)")!
    }
}

enum MapRefreshInterval: Int, CaseIterable, Identifiable {
    case sec30 = 30
    case min1 = 60
    case min5 = 300
    case min15 = 900
    case min30 = 1800

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sec30: return "30 seconds"
        case .min1: return "1 minute"
        case .min5: return "5 minutes"
        case .min15: return "15 minutes"
        case .min30: return "30 minutes"
        }
    }
}

enum SpeedTestInterval: Int, CaseIterable, Identifiable {
    case sec1 = 1
    case sec5 = 5
    case sec10 = 10
    case sec30 = 30
    case min1 = 60
    case min5 = 300
    case min15 = 900

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sec1: return "1 second"
        case .sec5: return "5 seconds"
        case .sec10: return "10 seconds"
        case .sec30: return "30 seconds"
        case .min1: return "1 minute"
        case .min5: return "5 minutes"
        case .min15: return "15 minutes"
        }
    }
}

enum UploadPayloadSize: Int, CaseIterable, Identifiable {
    case kb500 = 500_000
    case mb1 = 1_000_000
    case mb2 = 2_000_000
    case mb5 = 5_000_000
    case mb10 = 10_000_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .kb500: return "500 KB"
        case .mb1: return "1 MB"
        case .mb2: return "2 MB"
        case .mb5: return "5 MB"
        case .mb10: return "10 MB"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("downloadTestSize") private var downloadTestSizeRaw: String = DownloadTestSize.mb10.rawValue
    @AppStorage("uploadPayloadSize") private var uploadPayloadSizeRaw: Int = UploadPayloadSize.mb2.rawValue
    @AppStorage("speedTestIntervalSeconds") private var speedTestIntervalRaw: Int = SpeedTestInterval.sec5.rawValue
    @AppStorage("viewOnlyMode") private var viewOnlyMode: Bool = false
    @AppStorage("mapRefreshIntervalSeconds") private var mapRefreshIntervalRaw: Int = MapRefreshInterval.min1.rawValue
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = false
    @AppStorage("signalDataDisplayMode") private var signalDataDisplayModeRaw: String = SignalDataDisplayMode.numbersAndCircles.rawValue
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userPassword") private var userPassword: String = ""
    @AppStorage("userCarrier") private var userCarrier: String = ""
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("hasRegisteredBefore") private var hasRegisteredBefore: Bool = false

    @State private var cacheSnapshot = SignalCircleCache.snapshot()
    @State private var showClearCacheConfirmation = false
    @State private var showResetPasswordPrompt = false
    @State private var showResetPasswordResult = false
    @State private var newPassword = ""
    @State private var resetPasswordResultTitle = ""
    @State private var resetPasswordResultMessage = ""
    @State private var isResettingPassword = false
    @State private var availableCarriers: [String] = []
    @State private var selectedNewCarrier = ""
    @State private var isChangingCarrier = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false

    private var mapRefreshInterval: Binding<MapRefreshInterval> {
        Binding(
            get: { MapRefreshInterval(rawValue: mapRefreshIntervalRaw) ?? .min1 },
            set: { mapRefreshIntervalRaw = $0.rawValue }
        )
    }

    private var carrierOptions: [String] {
        guard !userCarrier.isEmpty, !availableCarriers.contains(userCarrier) else {
            return availableCarriers
        }
        return [userCarrier] + availableCarriers
    }
    
    private var speedTestInterval: Binding<SpeedTestInterval> {
        Binding(
            get: { SpeedTestInterval(rawValue: speedTestIntervalRaw) ?? .sec5 },
            set: { speedTestIntervalRaw = $0.rawValue }
        )
    }

    private var downloadTestSize: Binding<DownloadTestSize> {
        Binding(
            get: { DownloadTestSize(rawValue: downloadTestSizeRaw) ?? .mb10 },
            set: { downloadTestSizeRaw = $0.rawValue }
        )
    }

    private var uploadPayloadSize: Binding<UploadPayloadSize> {
        Binding(
            get: { UploadPayloadSize(rawValue: uploadPayloadSizeRaw) ?? .mb2 },
            set: { uploadPayloadSizeRaw = $0.rawValue }
        )
    }

    private var signalDataDisplayMode: Binding<SignalDataDisplayMode> {
        Binding(
            get: { SignalDataDisplayMode(rawValue: signalDataDisplayModeRaw) ?? .numbersAndCircles },
            set: { signalDataDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        accountHeaderCard
                        viewingCard
                        testingCard
                        mapCard
                        cacheCard
                        accountCard
                        deviceCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 36)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .foregroundStyle(.white)
            .tint(AppTheme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.ds(15, .bold))
                }
            }
            .onAppear {
                refreshCacheSnapshot()
                Task { await loadCarriers() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .signalCircleCacheDidChange)) { _ in
                refreshCacheSnapshot()
            }
            .alert("Clear cached map data?", isPresented: $showClearCacheConfirmation) {
                Button("Clear", role: .destructive) {
                    SignalCircleCache.clear()
                    refreshCacheSnapshot()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes locally saved map data. The next refresh will download points from the server again.")
            }
            .alert("Reset Password", isPresented: $showResetPasswordPrompt) {
                SecureField("New password", text: $newPassword)
                Button("Update") {
                    resetPassword()
                }
                Button("Cancel", role: .cancel) {
                    newPassword = ""
                }
            } message: {
                Text("Enter the new password for your account.")
            }
            .alert(resetPasswordResultTitle, isPresented: $showResetPasswordResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetPasswordResultMessage)
            }
            .alert("Delete account permanently?", isPresented: $showDeleteAccountConfirmation) {
                Button("Delete Account", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes your account. You will be signed out and need to register again to use this account.")
            }
        }
    }

    // MARK: - Cards

    private var accountHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: 54, height: 54)
                    .blur(radius: 13)
                    .opacity(0.55)

                Text(userInitial)
                    .font(.ds(21, .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular, in: Circle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(userName.isEmpty ? "Not signed in" : userName)
                    .font(.ds(18, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    if !userCarrier.isEmpty {
                        GlassBadge(text: userCarrier, systemImage: "antenna.radiowaves.left.and.right")
                    }

                    GlassBadge(
                        text: viewOnlyMode ? "View only" : "Contributing",
                        systemImage: viewOnlyMode ? "eye.fill" : "dot.radiowaves.up.forward",
                        tint: viewOnlyMode ? AppTheme.muted : AppTheme.good
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }

    private var viewingCard: some View {
        GlassCard(title: "Viewing", systemImage: "eye.fill") {
            VStack(spacing: 0) {
                GlassToggleRow(title: "View only mode", systemImage: "eye", isOn: $viewOnlyMode)

                GlassNote("Shows the connectivity map without running speed tests or submitting your data.")

                GlassDivider()

                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 11) {
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 20)

                        Text("Data display")
                            .font(.ds(15, .medium))
                            .foregroundStyle(.white)

                        Spacer(minLength: 0)
                    }

                    GlassSegmented(
                        options: SignalDataDisplayMode.allCases.map { (label: $0.label, value: $0) },
                        selection: signalDataDisplayMode
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
        }
    }

    private var testingCard: some View {
        GlassCard(title: "Speed testing", systemImage: "speedometer") {
            VStack(spacing: 0) {
                GlassMenuRow(
                    title: "Test interval",
                    systemImage: "timer",
                    options: SpeedTestInterval.allCases.map { (label: $0.label, value: $0) },
                    selection: speedTestInterval
                )

                GlassDivider()

                GlassMenuRow(
                    title: "Download size",
                    systemImage: "arrow.down.circle",
                    options: DownloadTestSize.allCases.map { (label: $0.label, value: $0) },
                    selection: downloadTestSize
                )

                GlassDivider()

                GlassMenuRow(
                    title: "Upload payload",
                    systemImage: "arrow.up.circle",
                    options: UploadPayloadSize.allCases.map { (label: $0.label, value: $0) },
                    selection: uploadPayloadSize
                )

                GlassNote("Larger files and more frequent tests give a denser, more accurate map but use more data.")
            }
        }
    }

    private var mapCard: some View {
        GlassCard(title: "Map", systemImage: "map.fill") {
            VStack(spacing: 0) {
                GlassMenuRow(
                    title: "Auto refresh",
                    systemImage: "arrow.clockwise",
                    options: MapRefreshInterval.allCases.map { (label: $0.label, value: $0) },
                    selection: mapRefreshInterval
                )

                GlassNote("How often the map pulls new points from the server.")
            }
        }
    }

    private var cacheCard: some View {
        GlassCard(title: "Offline cache", systemImage: "internaldrive.fill") {
            VStack(spacing: 0) {
                GlassStatRow(
                    title: "Cached points",
                    value: "\(cacheSnapshot.entryCount)",
                    systemImage: "mappin.circle"
                )

                GlassDivider()

                GlassStatRow(
                    title: "Data size",
                    value: cacheSnapshot.formattedByteCount,
                    systemImage: "shippingbox"
                )

                GlassDivider()

                GlassActionRow(
                    title: "Clear cached map data",
                    systemImage: "trash",
                    tint: AppTheme.bad,
                    isEnabled: cacheSnapshot.entryCount > 0
                ) {
                    showClearCacheConfirmation = true
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var accountCard: some View {
        GlassCard(title: "Account", systemImage: "person.crop.circle.fill") {
            VStack(spacing: 0) {
                GlassMenuRow(
                    title: "Carrier",
                    systemImage: "antenna.radiowaves.left.and.right",
                    options: carrierMenuOptions,
                    selection: $selectedNewCarrier,
                    isEnabled: !availableCarriers.isEmpty && !isChangingCarrier && !userName.isEmpty
                )
                .onChange(of: selectedNewCarrier) { _, newCarrier in
                    guard !newCarrier.isEmpty, newCarrier != userCarrier else { return }
                    changeCarrier(to: newCarrier)
                }

                GlassDivider()

                GlassActionRow(
                    title: "Reset password",
                    systemImage: "key.fill",
                    isBusy: isResettingPassword,
                    isEnabled: !userName.isEmpty
                ) {
                    newPassword = ""
                    showResetPasswordPrompt = true
                }

                GlassDivider()

                GlassActionRow(
                    title: "Delete account",
                    systemImage: "person.crop.circle.badge.xmark",
                    tint: AppTheme.bad,
                    isBusy: isDeletingAccount,
                    isEnabled: !userName.isEmpty && !userPassword.isEmpty
                ) {
                    showDeleteAccountConfirmation = true
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var deviceCard: some View {
        GlassCard(title: "Device", systemImage: "iphone") {
            VStack(spacing: 0) {
                GlassToggleRow(title: "Keep screen awake", systemImage: "sun.max.fill", isOn: $keepScreenAwake)

                GlassNote("Prevents your device from locking while the app is open. Uses more battery.")
            }
        }
    }

    private var userInitial: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// Carrier choices for the account picker, including a placeholder when the
    /// user has not set one yet.
    private var carrierMenuOptions: [(label: String, value: String)] {
        var options: [(label: String, value: String)] = []
        if userCarrier.isEmpty {
            options.append((label: "Not set", value: ""))
        }
        options.append(contentsOf: carrierOptions.map { (label: $0, value: $0) })
        return options
    }

    private func refreshCacheSnapshot() {
        cacheSnapshot = SignalCircleCache.snapshot()
    }

    private func resetPassword() {
        let trimmedUsername = userName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !newPassword.isEmpty else {
            showResetPasswordResult(title: "Password not changed", message: "Enter a new password first.")
            return
        }

        guard !trimmedUsername.isEmpty, !userPassword.isEmpty else {
            showResetPasswordResult(
                title: "Password not changed",
                message: "Your current password is not stored yet. Log out and log back in, then try again."
            )
            return
        }

        let requestedPassword = newPassword
        isResettingPassword = true

        NetworkLogger.shared.resetPassword(
            username: trimmedUsername,
            currentPassword: userPassword,
            newPassword: requestedPassword
        ) { error in
            DispatchQueue.main.async {
                isResettingPassword = false

                if let error {
                    showResetPasswordResult(title: "Password not changed", message: error.localizedDescription)
                    return
                }

                userPassword = requestedPassword
                newPassword = ""
                showResetPasswordResult(title: "Password updated", message: "Your saved password was updated for future account actions.")
            }
        }
    }

    private func loadCarriers() async {
        guard let url = URL(string: "https://api.kalculator.lol/carriers") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return }
            let names = try JSONDecoder().decode([String].self, from: data)
            await MainActor.run {
                availableCarriers = names
                selectedNewCarrier = userCarrier
            }
        } catch {
            print("Failed to load carriers:", error)
        }
    }

    private func changeCarrier(to requestedCarrier: String) {
        let trimmedUsername = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !userPassword.isEmpty else {
            selectedNewCarrier = userCarrier
            showResetPasswordResult(
                title: "Carrier not changed",
                message: "Your saved username or password is missing. Log out and log back in, then try again."
            )
            return
        }
        guard !requestedCarrier.isEmpty, requestedCarrier != userCarrier else { return }

        isChangingCarrier = true
        NetworkLogger.shared.changeCarrier(
            username: trimmedUsername,
            password: userPassword,
            newCarrier: requestedCarrier
        ) { error in
            DispatchQueue.main.async {
                isChangingCarrier = false
                if let error {
                    selectedNewCarrier = userCarrier
                    showResetPasswordResult(title: "Carrier not changed", message: error.localizedDescription)
                    return
                }
                userCarrier = requestedCarrier
                selectedNewCarrier = requestedCarrier
                showResetPasswordResult(title: "Carrier updated", message: "Your carrier has been changed.")
            }
        }
    }

    private func deleteAccount() {
        let trimmedUsername = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !userPassword.isEmpty else {
            showResetPasswordResult(title: "Account not deleted", message: "Your saved username or password is missing. Log out and log back in, then try again.")
            return
        }

        isDeletingAccount = true
        NetworkLogger.shared.deleteAccount(username: trimmedUsername, password: userPassword) { error in
            DispatchQueue.main.async {
                isDeletingAccount = false
                if let error {
                    showResetPasswordResult(title: "Account not deleted", message: error.localizedDescription)
                    return
                }

                userName = ""
                userPassword = ""
                userCarrier = ""
                selectedNewCarrier = ""
                hasRegisteredBefore = false
                isLoggedIn = false
                dismiss()
            }
        }
    }

    private func showResetPasswordResult(title: String, message: String) {
        resetPasswordResultTitle = title
        resetPasswordResultMessage = message
        showResetPasswordResult = true
    }
}
