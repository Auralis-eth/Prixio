import Foundation

/// On-disk LRU cache shared by the on-device-model enrichment passes (name
/// enrichment, entry parsing, category suggestion): string keys, one Codable value
/// each. The inputs these passes see repeat heavily (flyer names week to week, list
/// entries, merchants), so after the first answer most lookups never touch the
/// model. Bounded by least-recent-use pruning; all I/O failures degrade to
/// "no cache".
actor EnrichmentDiskCache<Value: Codable & Sendable> {
    private struct Stored: Codable {
        let value: Value
        var lastUsedAt: Date
    }

    private let fileURL: URL
    /// Cap on cached keys; the oldest-used entries are pruned past it.
    private let maxEntries: Int
    private var entries: [String: Stored]?

    init(fileURL: URL, maxEntries: Int) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
    }

    func lookup(_ key: String) -> Value? {
        lookup([key])[key]
    }

    /// The cached values present for `keys`, refreshing their last-used timestamps.
    func lookup(_ keys: [String]) -> [String: Value] {
        loadIfNeeded()
        var out: [String: Value] = [:]
        let now = Date.now
        for key in keys {
            guard var stored = entries?[key] else { continue }
            stored.lastUsedAt = now
            entries?[key] = stored
            out[key] = stored.value
        }
        return out
    }

    func store(_ key: String, value: Value) {
        store([key: value])
    }

    func store(_ new: [String: Value]) {
        loadIfNeeded()
        var merged = entries ?? [:]
        let now = Date.now
        for (key, value) in new {
            merged[key] = Stored(value: value, lastUsedAt: now)
        }
        if merged.count > maxEntries {
            let keep = merged.sorted { $0.value.lastUsedAt > $1.value.lastUsedAt }
                .prefix(maxEntries)
            merged = Dictionary(uniqueKeysWithValues: Array(keep))
        }
        entries = merged
        persist()
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Stored].self, from: data) else {
            entries = [:]
            return
        }
        entries = decoded
    }

    private func persist() {
        guard let entries, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
