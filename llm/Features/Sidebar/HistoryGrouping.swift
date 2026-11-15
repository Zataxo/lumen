import Foundation

nonisolated enum HistoryBucket: Int, CaseIterable, Comparable, Sendable {
    case today, yesterday, previous7Days, older

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .previous7Days: "Previous 7 Days"
        case .older: "Older"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct HistoryGroup<Item>: Identifiable {
    var bucket: HistoryBucket
    var items: [Item]
    var id: HistoryBucket { bucket }
}

/// Buckets chat history by calendar day relative to `now`.
nonisolated enum HistoryGrouping {
    static func bucket(for date: Date, now: Date = .now, calendar: Calendar = .current) -> HistoryBucket {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today } // includes slightly-future clock skew
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfWeekWindow = calendar.date(byAdding: .day, value: -7, to: startOfToday)
        else { return .older }
        if date >= startOfYesterday { return .yesterday }
        if date >= startOfWeekWindow { return .previous7Days }
        return .older
    }

    /// Groups items (assumed newest-first) into ordered, non-empty buckets, preserving order
    /// within each bucket. Single pass, so it stays instant for thousands of chats.
    static func group<Item>(
        _ items: [Item],
        date: (Item) -> Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HistoryGroup<Item>] {
        var buckets: [HistoryBucket: [Item]] = [:]
        for item in items {
            buckets[bucket(for: date(item), now: now, calendar: calendar), default: []].append(item)
        }
        return HistoryBucket.allCases.compactMap { bucket in
            guard let items = buckets[bucket], !items.isEmpty else { return nil }
            return HistoryGroup(bucket: bucket, items: items)
        }
    }
}
