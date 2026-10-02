//
//  NetworkClient.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/10/26.
//
import Foundation

final class NetworkClient {
    static let shared = NetworkClient()

    func get<T: Decodable>(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        as type: T.Type,
        completion: @escaping (T?, Error?) -> Void
    ) {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = "GET"
        if cachePolicy == .reloadIgnoringLocalCacheData {
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = data else {
                completion(nil, NSError(domain: "NetworkClient", code: -1))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(decoded, nil)
            } catch {
                completion(nil, error)
            }
        }.resume()
    }
}
