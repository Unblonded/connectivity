//
//  NetworkLogger.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import Foundation
import CoreLocation

struct SpeedTestResult: Codable {
    let latitude: Double
    let longitude: Double
    let downloadMbps: Double?
    let uploadMbps: Double?
}

final class NetworkLogger {
    static let shared = NetworkLogger()

    // Replace with your actual logging endpoint
    private let endpoint = URL(string: "https://api.kalculator.lol/debug")!

    func logResult(_ result: SpeedTestResult, completion: ((Error?) -> Void)? = nil) {
        var dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(result))) as? [String: Any] ?? [:]
        dict["token"] = "CONGRESSIONAL-APP-CHALLENGE-ANTI-SPAM"

        guard let body = try? JSONSerialization.data(withJSONObject: dict) else {
            completion?(NSError(domain: "NetworkLogger", code: -1))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            completion?(error)
        }.resume()
    }
}
