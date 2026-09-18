//
//  NetworkStatusMonitor.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/18/26.
//
import Foundation
import Network

final class NetworkStatusMonitor: @unchecked Sendable {
    static let shared = NetworkStatusMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkStatusMonitor")
    private let lock = NSLock()
    private var _isUsingWiFi = false

    var isUsingWiFi: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isUsingWiFi
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.setIsUsingWiFi(path.usesInterfaceType(.wifi))
        }
        monitor.start(queue: queue)
    }

    private func setIsUsingWiFi(_ isUsingWiFi: Bool) {
        lock.lock()
        _isUsingWiFi = isUsingWiFi
        lock.unlock()
    }
}
