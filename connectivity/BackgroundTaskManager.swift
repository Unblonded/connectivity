//
//  BackgroundTaskManager.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import Foundation
import BackgroundTasks
import CoreLocation

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    static let taskIdentifier = "unblonded.prod.speedtest"

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // iOS treats this as a minimum, not a guarantee
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        schedule() // reschedule for next time immediately

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        runSpeedTestAndLog {
            task.setTaskCompleted(success: true)
        }
    }

    private let runLock = NSLock()
    private var isRunning = false

    /// Short test intervals (1–5s) are shorter than a test takes on a slow
    /// link, so without this guard runs pile up and skew each other's timing.
    private func beginRun() -> Bool {
        runLock.lock(); defer { runLock.unlock() }
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    private func endRun() {
        runLock.lock(); isRunning = false; runLock.unlock()
    }

    private func setPhase(_ phase: TelemetryPhase) {
        Task { @MainActor in LiveTelemetry.shared.setPhase(phase) }
    }

    func runSpeedTestAndLog(completion: (() -> Void)? = nil) {
        guard !NetworkStatusMonitor.shared.isUsingWiFi else {
            UserStore.shared.updateSpeed(downloadMbps: nil, uploadMbps: nil)
            setPhase(.wifiPaused)
            completion?()
            return
        }

        guard beginRun() else {
            completion?()
            return
        }

        setPhase(.download)
        SpeedTest.shared.measureDownload { downloadMbps, error in
            if let error = error {
                print("Download test failed: \(error)")
            }
            self.setPhase(.upload)
            SpeedTest.shared.measureUpload { uploadMbps, error in
                if let error = error {
                    print("Upload test failed: \(error)")
                }
                self.reportResult(downloadMbps: downloadMbps, uploadMbps: uploadMbps)
                Task { @MainActor in
                    LiveTelemetry.shared.record(downloadMbps: downloadMbps, uploadMbps: uploadMbps)
                }
                self.endRun()
                completion?()
            }
        }
    }

    private func reportResult(downloadMbps: Double?, uploadMbps: Double?) {
        let coord = UserStore.shared.coordinate
        let result = SpeedTestResult(
            latitude: coord.latitude,
            longitude: coord.longitude,
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps
        )
        NetworkLogger.shared.logResult(result) { error in
            if let error = error {
                print("Log failed: \(error)")
            }
        }
    }
}
