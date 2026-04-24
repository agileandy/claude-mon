import Foundation

enum SessionAnalyzer {
    static let blockWindow: TimeInterval = 5 * 3600  // 5 hours

    static func analyze(entries: [UsageEntry], now: Date = Date()) -> [SessionBlock] {
        guard !entries.isEmpty else { return [] }

        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var groups: [[UsageEntry]] = []
        var current: [UsageEntry] = [sorted[0]]

        for entry in sorted.dropFirst() {
            let gap = entry.timestamp.timeIntervalSince(current.last!.timestamp)
            let elapsedFromStart = entry.timestamp.timeIntervalSince(current.first!.timestamp)
            // Start a new block when either:
            //   - there's a >5h silence (no activity), or
            //   - the current block's 5h rate-limit window has closed.
            if gap > blockWindow || elapsedFromStart > blockWindow {
                groups.append(current)
                current = [entry]
            } else {
                current.append(entry)
            }
        }
        groups.append(current)

        return groups.map { SessionBlock.build(from: $0, now: now) }
    }

    static func activeBlock(in blocks: [SessionBlock]) -> SessionBlock? {
        blocks.last(where: { $0.isActive })
    }
}
