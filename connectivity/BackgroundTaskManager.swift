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

    func runSpeedTestAndLog(completion: (() -> Void)? = nil) {
        SpeedTest.shared.measureDownload { downloadMbps, error in
            if let error = error {
                print("Download test failed: \(error)")
            }
            SpeedTest.shared.measureUpload { uploadMbps, error in
                if let error = error {
                    print("Upload test failed: \(error)")
                }
                self.reportResult(downloadMbps: downloadMbps, uploadMbps: uploadMbps)
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
