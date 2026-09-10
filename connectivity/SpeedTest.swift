//
//  SpeedTest.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import Foundation

final class SpeedTest {
    static let shared = SpeedTest()

    // Swap these for URLs you control/trust for testing throughput
    private let downloadTestURL = URL(string: "https://ftp.bit.nl/speedtest/10mb.bin")!
    private let uploadTestURL = URL(string: "https://httpbin.org/post")!

    func measureDownload(completion: @escaping (Double?, Error?) -> Void) {
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

    func measureUpload(completion: @escaping (Double?, Error?) -> Void) {
        let payload = Data(count: 2_000_000) // 2MB dummy payload
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
}
