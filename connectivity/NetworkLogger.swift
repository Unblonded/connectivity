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

struct AuthRequest: Codable {
    let username: String
    let password: String
}

final class NetworkLogger {
    static let shared = NetworkLogger()

    private let sampleEndpoint = URL(string: "https://api.kalculator.lol/samples")!
    private let registerEndpoint = URL(string: "https://api.kalculator.lol/register")!
    private let loginEndpoint = URL(string: "https://api.kalculator.lol/login")!
    
    func register(username: String, password: String, completion: @escaping (Error?) -> Void) {
        sendAuthRequest(to: registerEndpoint, username: username, password: password, completion: completion)
    }

    func login(username: String, password: String, completion: @escaping (Error?) -> Void) {
        sendAuthRequest(to: loginEndpoint, username: username, password: password, completion: completion)
    }

    func logResult(_ result: SpeedTestResult, completion: ((Error?) -> Void)? = nil) {
        // Update UserStore with latest speeds before sending
        UserStore.shared.updateSpeed(downloadMbps: result.downloadMbps, uploadMbps: result.uploadMbps)

        let username = UserDefaults.standard.string(forKey: "userName") ?? ""

        var dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(result))) as? [String: Any] ?? [:]
        dict["username"] = username

        guard let body = try? JSONSerialization.data(withJSONObject: dict) else {
            completion?(NSError(domain: "NetworkLogger", code: -1))
            return
        }

        var request = URLRequest(url: sampleEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            completion?(error)
        }.resume()
    }

    private func sendAuthRequest(
        to endpoint: URL,
        username: String,
        password: String,
        completion: @escaping (Error?) -> Void
    ) {
        let authRequest = AuthRequest(username: username, password: password)

        guard let body = try? JSONEncoder().encode(authRequest) else {
            completion(NSError(domain: "NetworkLogger", code: -1))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(NSError(domain: "NetworkLogger", code: -2))
                return
            }

            completion(nil)
        }.resume()
    }
}
