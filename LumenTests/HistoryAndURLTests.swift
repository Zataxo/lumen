import Foundation
import Testing
@testable import Lumen

@Suite("History grouping")
struct HistoryGroupingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// Wednesday 2026-11-18 10:30 Paris time.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10, minute: 30))!
    }

    private func date(dayOffset: Int, hour: Int = 12, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test func buckets() {
        func bucket(_ date: Date) -> HistoryBucket { HistoryGrouping.bucket(for: date, now: now, calendar: calendar) }
        #expect(bucket(date(dayOffset: 0, hour: 0, minute: 0)) == .today)
        #expect(bucket(now) == .today)
        #expect(bucket(now.addingTimeInterval(120)) == .today) // clock skew
        #expect(bucket(date(dayOffset: -1, hour: 23, minute: 59)) == .yesterday)
        #expect(bucket(date(dayOffset: -1, hour: 0)) == .yesterday)
        #expect(bucket(date(dayOffset: -2)) == .previous7Days)
        #expect(bucket(date(dayOffset: -7, hour: 0)) == .previous7Days)
        #expect(bucket(date(dayOffset: -8, hour: 23)) == .older)
        #expect(bucket(.distantPast) == .older)
    }

    @Test func justBeforeMidnightIsYesterday() {
        let midnight = calendar.startOfDay(for: now)
        #expect(HistoryGrouping.bucket(for: midnight.addingTimeInterval(-1), now: now, calendar: calendar) == .yesterday)
    }

    @Test func groupsInOrderAndSkipsEmptyBuckets() {
        let items: [(String, Date)] = [
            ("a", date(dayOffset: 0)),
            ("b", date(dayOffset: 0, hour: 1)),
            ("c", date(dayOffset: -3)),
            ("d", date(dayOffset: -30)),
        ]
        let groups = HistoryGrouping.group(items, date: \.1, now: now, calendar: calendar)
        #expect(groups.map(\.bucket) == [.today, .previous7Days, .older])
        #expect(groups[0].items.map(\.0) == ["a", "b"])
        #expect(groups[1].items.map(\.0) == ["c"])
    }

    @Test func groupsThousandsOfChatsQuickly() {
        let items = (0..<5000).map { index in date(dayOffset: -(index % 60)) }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = HistoryGrouping.group(items, date: { $0 }, now: now, calendar: calendar)
        }
        #expect(elapsed < .milliseconds(250))
    }
}

@Suite("URL handling")
struct URLNormalizerTests {
    @Test(arguments: [
        ("192.168.1.50:11434", "http://192.168.1.50:11434"),
        ("http://192.168.1.50:11434/", "http://192.168.1.50:11434"),
        ("  https://example.com/v1/ ", "https://example.com/v1"),
        ("mac-studio.local:11434", "http://mac-studio.local:11434"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(URLNormalizer.normalizedBaseURL(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "ftp://host", "http://", "not a url with spaces://x"])
    func rejects(input: String) {
        #expect(URLNormalizer.normalizedBaseURL(from: input) == nil)
    }

    @Test func localNetworkHosts() {
        #expect(URLNormalizer.isLocalNetworkHost("192.168.1.5"))
        #expect(URLNormalizer.isLocalNetworkHost("10.0.0.2"))
        #expect(URLNormalizer.isLocalNetworkHost("172.20.1.1"))
        #expect(URLNormalizer.isLocalNetworkHost("100.101.102.103"))
        #expect(URLNormalizer.isLocalNetworkHost("studio.local"))
        #expect(URLNormalizer.isLocalNetworkHost("nas"))
        #expect(!URLNormalizer.isLocalNetworkHost("172.32.0.1"))
        #expect(!URLNormalizer.isLocalNetworkHost("example.com"))
        #expect(!URLNormalizer.isLocalNetworkHost("8.8.8.8"))
    }

    @Test func parsesOllamaNanosecondDates() {
        let date = ServerDateParser.parse("2024-05-07T10:28:15.183538709-07:00")
        #expect(date == Date(timeIntervalSince1970: 1_715_102_895))
        #expect(ServerDateParser.parse("2024-05-07T17:28:15Z") == Date(timeIntervalSince1970: 1_715_102_895))
    }
}
