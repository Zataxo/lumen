import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import llm_app

@Suite("System prompt")
struct SystemPromptBuilderTests {
    @Test func baseOnly() {
        #expect(SystemPromptBuilder.build(base: "  Be brief. ", profile: nil) == "Be brief.")
    }

    @Test func profileOnly() {
        let prompt = SystemPromptBuilder.build(base: "", profile: ProfileContext(name: "Sam", aboutMe: "iOS developer"))
        #expect(prompt == "The user's name is Sam.\nAbout the user:\niOS developer")
    }

    @Test func baseAndProfileAreSeparated() {
        let prompt = SystemPromptBuilder.build(base: "Be brief.", profile: ProfileContext(name: "Sam", aboutMe: ""))
        #expect(prompt == "Be brief.\n\nThe user's name is Sam.")
    }

    @Test func nothingToSend() {
        #expect(SystemPromptBuilder.build(base: " ", profile: ProfileContext(name: " ", aboutMe: "")).isEmpty)
    }
}

@Suite("Greeting and initials")
struct GreetingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: hour))!
    }

    @Test(arguments: [(8, "Good morning, Sam"), (13, "Good afternoon, Sam"), (19, "Good evening, Sam"), (2, "Hello, Sam")])
    func greetsByTimeOfDay(hour: Int, expected: String) {
        #expect(Greeting.text(name: "Sam Rivera", date: at(hour: hour), calendar: calendar) == expected)
    }

    @Test func noProfile() {
        #expect(Greeting.text(name: nil) == "What can I help with?")
        #expect(Greeting.text(name: "") == "What can I help with?")
    }

    @Test(arguments: [("Sam Rivera", "SR"), ("madonna", "M"), ("ana-lucía pérez", "AL"), ("  ", "?"), ("Jean Paul Sartre", "JP")])
    func initials(name: String, expected: String) {
        #expect(Initials.from(name) == expected)
    }

    @Test func suggestionsAreDistinct() {
        let sample = PromptSuggestion.sample(4)
        #expect(sample.count == 4)
        #expect(Set(sample).count == 4)
    }
}

@Suite("Image downscaling")
struct ImageDownscalerTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func downscalesLongestSideAndKeepsAspect() throws {
        let original = try pngData(width: 2000, height: 1000)
        let thumbnail = try #require(ImageDownscaler.jpegThumbnail(from: original, maxPixelSize: 256))
        let size = try #require(ImageDownscaler.pixelSize(of: thumbnail))
        #expect(size == CGSize(width: 256, height: 128))
        #expect(thumbnail.count < original.count)
    }

    @Test func rejectsGarbage() {
        #expect(ImageDownscaler.jpegThumbnail(from: Data("not an image".utf8), maxPixelSize: 64) == nil)
    }
}
