import Foundation
@testable import ClaudeMonKit

@MainActor
func runSessionAnalyzerSuite(_ r: Runner) {
    // Pin a deterministic now so isActive boundaries don't depend on wall time.
    let now = Date(timeIntervalSince1970: 1_777_120_800)   // 2026-04-25 12:00 UTC

    func entry(id: String, hoursAgo: Double) -> UsageEntry {
        UsageEntry(
            id: id,
            timestamp: now.addingTimeInterval(-hoursAgo * 3600),
            sessionId: "s",
            model: "claude-sonnet-4",
            inputTokens: 1000,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectDir: "-test"
        )
    }

    r.test("sessionAnalyzer_empty_returnsNoBlocks") {
        let blocks = SessionAnalyzer.analyze(entries: [], now: now)
        try expectEqual(blocks.count, 0)
    }

    r.test("sessionAnalyzer_singleRecentEntry_oneActiveBlock") {
        // Entry from 1h ago — block window (5h after start) hasn't closed → active.
        let blocks = SessionAnalyzer.analyze(entries: [entry(id: "a", hoursAgo: 1)], now: now)
        try expectEqual(blocks.count, 1)
        try expect(blocks[0].isActive)
    }

    r.test("sessionAnalyzer_singleOldEntry_oneInactiveBlock") {
        // Entry from 6h ago — block window closed (start + 5h < now) → inactive.
        let blocks = SessionAnalyzer.analyze(entries: [entry(id: "a", hoursAgo: 6)], now: now)
        try expectEqual(blocks.count, 1)
        try expect(!blocks[0].isActive)
    }

    r.test("sessionAnalyzer_twoEntries4hApart_groupsToOneBlock") {
        // Gap 4h < blockWindow (5h) AND elapsed-from-start 4h ≤ blockWindow → one block.
        let entries = [
            entry(id: "a", hoursAgo: 4),
            entry(id: "b", hoursAgo: 0),
        ]
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        try expectEqual(blocks.count, 1)
        try expectEqual(blocks[0].messageCount, 2)
    }

    r.test("sessionAnalyzer_twoEntries6hApart_splitsIntoTwoBlocks") {
        // Gap 6h > blockWindow → silence triggers a new block.
        let entries = [
            entry(id: "a", hoursAgo: 6),
            entry(id: "b", hoursAgo: 0),
        ]
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        try expectEqual(blocks.count, 2)
        try expectEqual(blocks[0].messageCount, 1)
        try expectEqual(blocks[1].messageCount, 1)
    }

    r.test("sessionAnalyzer_continuous6hOfActivity_splitsAt5hElapsed") {
        // 7 entries every hour for 6 hours: blocks must split when elapsed-from-start
        // exceeds 5h, even though gaps are only 1h each.
        // hoursAgo: 6, 5, 4, 3, 2, 1, 0
        let entries = (0...6).map { i in
            entry(id: "e\(i)", hoursAgo: Double(6 - i))
        }
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        // First block: hoursAgo 6,5,4,3,2 (elapsed 4h ≤ 5h). Entry at hoursAgo=1
        // would push elapsed to 5h (not >); the `>` test means it joins. Entry at
        // hoursAgo=0 makes elapsed 6h > 5h → new block. So: 6 entries in block 0,
        // 1 entry in block 1.
        try expectEqual(blocks.count, 2)
        try expectEqual(blocks[0].messageCount, 6)
        try expectEqual(blocks[1].messageCount, 1)
    }

    r.test("sessionAnalyzer_activeBlock_findsLastActive") {
        // Two blocks: an old one (inactive) and a recent one (active).
        let entries = [
            entry(id: "old1", hoursAgo: 24),
            entry(id: "old2", hoursAgo: 23),
            entry(id: "new",  hoursAgo: 1),
        ]
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        let active = SessionAnalyzer.activeBlock(in: blocks)
        try expect(active != nil)
        try expectEqual(active?.messageCount, 1)
    }

    r.test("sessionAnalyzer_activeBlock_nilWhenAllOld") {
        let entries = [entry(id: "old", hoursAgo: 24)]
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        let active = SessionAnalyzer.activeBlock(in: blocks)
        try expect(active == nil)
    }
}
