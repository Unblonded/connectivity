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
    let carrier: String?
}

struct ResetPasswordRequest: Codable {
    let username: String
    let currentPassword: String
    let newPassword: String
}

struct ChangeCarrierRequest: Codable {
    let username: String
    let password: String
    let newCarrier: String
}

private enum NetworkLoggerError: LocalizedError {
    case encodingFailed
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not prepare the request."
        case .requestFailed(_, let message):
            return message ?? "The server rejected the request."
        }
    }
}

final class NetworkLogger {
    static let shared = NetworkLogger()

    private let sampleEndpoint = URL(string: "https://api.kalculator.lol/samples")!
    private let registerEndpoint = URL(string: "https://api.kalculator.lol/register")!
    private let loginEndpoint = URL(string: "https://api.kalculator.lol/login")!
    private let resetPasswordEndpoint = URL(string: "https://api.kalculator.lol/reset-password")!
    private let changeCarrierEndpoint = URL(string: "https://api.kalculator.lol/change-carrier")!
    
    func register(username: String, password: String, carrier: String, completion: @escaping (Error?) -> Void) {
        let request = AuthRequest(username: username, password: password, carrier: carrier)
        sendJSONRequest(to: registerEndpoint, body: request, completion: completion)
    }

    func login(username: String, password: String, completion: @escaping (Error?) -> Void) {
        sendAuthRequest(to: loginEndpoint, username: username, password: password, completion: completion)
    }

    func resetPassword(
        username: String,
        currentPassword: String,
        newPassword: String,
        completion: @escaping (Error?) -> Void
    ) {
        let resetRequest = ResetPasswordRequest(
            username: username,
            currentPassword: currentPassword,
            newPassword: newPassword
        )

        sendJSONRequest(to: resetPasswordEndpoint, body: resetRequest, completion: completion)
    }

    func changeCarrier(
        username: String,
        password: String,
        newCarrier: String,
        completion: @escaping (Error?) -> Void
    ) {
        let request = ChangeCarrierRequest(
            username: username,
            password: password,
            newCarrier: newCarrier
        )
        sendJSONRequest(to: changeCarrierEndpoint, body: request, completion: completion)
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
        let authRequest = AuthRequest(username: username, password: password, carrier: nil)
        sendJSONRequest(to: endpoint, body: authRequest, completion: completion)
    }

    private func sendJSONRequest<T: Encodable>(
        to endpoint: URL,
        body encodableBody: T,
        completion: @escaping (Error?) -> Void
    ) {
        guard let body = try? JSONEncoder().encode(encodableBody) else {
            completion(NetworkLoggerError.encodingFailed)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(NetworkLoggerError.requestFailed(statusCode: -1, message: nil))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(NetworkLoggerError.requestFailed(statusCode: httpResponse.statusCode, message: self.serverErrorMessage(from: data)))
                return
            }

            completion(nil)
        }.resume()
    }

    private func serverErrorMessage(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["error"] as? String,
              !message.isEmpty else {
            return nil
        }

        return message
    }
}
