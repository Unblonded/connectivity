//
//  SpeedTest.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import Foundation

final class SpeedTest {
    static let shared = SpeedTest()

    private var uploadTestURL = URL(string: "https://httpbin.org/post")!

    func measureUpload(completion: @escaping (Double?, Error?) -> Void) {
        let sizeRaw = UserDefaults.standard.object(forKey: "uploadPayloadSize") as? Int ?? UploadPayloadSize.mb2.rawValue
        let payload = Data(count: sizeRaw)

        var request = URLRequest(url: uploadTestURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let start = Date()
        let task = URLSession.shared.uploadTask(with: request, from: payload) { _, response, error in
            guard error == nil else {
                completion(nil, error)
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            let bytes = Double(payload.count)
            let mbps = (bytes * 8 / 1_000_000) / elapsed
            completion(mbps, nil)
        }
        task.resume()
    }

    func measureDownload(completion: @escaping (Double?, Error?) -> Void) {
        let sizeRaw = UserDefaults.standard.string(forKey: "downloadTestSize") ?? DownloadTestSize.mb10.rawValue
        let size = DownloadTestSize(rawValue: sizeRaw) ?? .mb10
        let downloadTestURL = size.url

        let start = Date()
        let task = URLSession.shared.dataTask(with: downloadTestURL) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil, error)
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            let bytes = Double(data.count)
            let mbps = (bytes * 8 / 1_000_000) / elapsed
            completion(mbps, nil)
        }
        task.resume()
    }
}
