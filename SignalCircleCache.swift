//
//  SignalCircleCache.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/22/26.
//

import Foundation

extension Notification.Name {
    static let signalCircleCacheDidChange = Notification.Name("signalCircleCacheDidChange")
}

struct SignalCircleCacheSnapshot {
    let entryCount: Int
    let byteCount: Int

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

enum SignalCircleCache {
    private static let entriesKey = "cachedSignalCircleEntries"

    static func loadEntries() -> [SignalCircleJSON] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey) else { return [] }

        do {
            return try JSONDecoder().decode([SignalCircleJSON].self, from: data)
        } catch {
            print("Failed to decode cached signal circles: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    static func store(newEntries: [SignalCircleJSON]) -> [SignalCircleJSON] {
        let cachedEntries = loadEntries()
        let mergedEntries = merge(cachedEntries + newEntries)
        save(mergedEntries)
        return mergedEntries
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: entriesKey)
        NotificationCenter.default.post(name: .signalCircleCacheDidChange, object: nil)
    }

    static func snapshot() -> SignalCircleCacheSnapshot {
        SignalCircleCacheSnapshot(
            entryCount: loadEntries().count,
            byteCount: UserDefaults.standard.data(forKey: entriesKey)?.count ?? 0
        )
    }

    static func highestID(in entries: [SignalCircleJSON]? = nil) -> Int {
        (entries ?? loadEntries()).map(\.id).max() ?? 0
    }

    private static func save(_ entries: [SignalCircleJSON]) {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: entriesKey)
            NotificationCenter.default.post(name: .signalCircleCacheDidChange, object: nil)
        } catch {
            print("Failed to cache signal circles: \(error.localizedDescription)")
        }
    }

    private static func merge(_ entries: [SignalCircleJSON]) -> [SignalCircleJSON] {
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            .values
            .sorted { $0.id < $1.id }
    }
}
