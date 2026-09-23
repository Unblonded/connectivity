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

    @State private var cacheSnapshot = SignalCircleCache.snapshot()
    @State private var showClearCacheConfirmation = false
    @State private var showResetPasswordPrompt = false
    @State private var showResetPasswordResult = false
    @State private var newPassword = ""
    @State private var resetPasswordResultTitle = ""
    @State private var resetPasswordResultMessage = ""
    @State private var isResettingPassword = false

    private var mapRefreshInterval: Binding<MapRefreshInterval> {
        Binding(
            get: { MapRefreshInterval(rawValue: mapRefreshIntervalRaw) ?? .min1 },
            set: { mapRefreshIntervalRaw = $0.rawValue }
        )
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
            Form {
                Section("Download test") {
                    Picker("File size", selection: downloadTestSize) {
                        ForEach(DownloadTestSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    Text("Larger files give more accurate results on fast connections but take longer and use more data.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }

                Section("Upload test") {
                    Picker("Payload size", selection: uploadPayloadSize) {
                        ForEach(UploadPayloadSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                }
                
                Section("Test frequency") {
                    Picker("Run speed test every", selection: speedTestInterval) {
                        ForEach(SpeedTestInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    Text("More frequent tests give a denser map but use more data.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
                
                Section("Viewing Options") {
                    Toggle("View only mode", isOn: $viewOnlyMode)
                    Text("When enabled, the app shows the connectivity map without running speed tests or submitting your data.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)

                    Picker("Data Display", selection: signalDataDisplayMode) {
                        ForEach(SignalDataDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Map refresh") {
                    Picker("Refresh map every", selection: mapRefreshInterval) {
                        ForEach(MapRefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                }

                Section("Map data cache") {
                    HStack {
                        Text("Cached points")
                        Spacer()
                        Text("\(cacheSnapshot.entryCount)")
                            .foregroundStyle(AppTheme.muted)
                    }

                    HStack {
                        Text("Data size")
                        Spacer()
                        Text(cacheSnapshot.formattedByteCount)
                            .foregroundStyle(AppTheme.muted)
                    }

                    Button("Clear cached map data", role: .destructive) {
                        showClearCacheConfirmation = true
                    }
                    .disabled(cacheSnapshot.entryCount == 0)
                }

                Section("Account Management") {
                    Button {
                        newPassword = ""
                        showResetPasswordPrompt = true
                    } label: {
                        if isResettingPassword {
                            ProgressView()
                        } else {
                            Text("Reset Password")
                        }
                    }
                    .disabled(isResettingPassword || userName.isEmpty)
                }
                
                Section("Display Idle Timeout") {
                    Toggle("Keep screen awake", isOn: $keepScreenAwake)
                    Text("Prevents your device from locking while the app is open. Uses more battery.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .foregroundStyle(.white)
            .tint(AppTheme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: refreshCacheSnapshot)
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
        }
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

    private func showResetPasswordResult(title: String, message: String) {
        resetPasswordResultTitle = title
        resetPasswordResultMessage = message
        showResetPasswordResult = true
    }
}
