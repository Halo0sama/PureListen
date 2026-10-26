import XCTest
@testable import PureListenCore

final class BiliAudioQualityTests: XCTestCase {
    private var dash: [String: Any] {
        ["audio": [
            ["id": 30216, "baseUrl": "https://example.com/low", "bandwidth": 64000],
            ["id": 30280, "baseUrl": "https://example.com/high", "bandwidth": 192000],
            ["id": 30232, "base_url": "https://example.com/standard", "bandwidth": 132000],
            ["id": 30250, "baseUrl": "https://example.com/dolby", "bandwidth": 448000]],
         "flac": ["audio": ["id": 30251, "base_url": "https://example.com/hires",
                             "bandwidth": 1500000, "codecs": "fLaC"]]]
    }

    func testPreferencesSelectActualTracks() throws {
        for (quality, suffix) in [(BiliAudioQuality.hires, "hires"), (.high, "high"), (.standard, "standard"), (.low, "low")] {
            let stream = try XCTUnwrap(SourceResolver.biliAudio(in: dash, quality: quality))
            XCTAssertEqual(stream.url, "https://example.com/" + suffix)
        }
        let hires = try XCTUnwrap(SourceResolver.biliAudio(in: dash, quality: .hires))
        XCTAssertEqual(hires.quality, "Hi-Res")
        XCTAssertEqual(hires.codec, "fLaC")
        XCTAssertEqual(hires.bitrate, 1500000)
    }

    func testMissingOrUnavailableHiresFallsBackWithoutFalseLabel() throws {
        for flac: Any in [NSNull(), ["audio": NSNull()], ["audio": ["baseUrl": ""]]] {
            var value = dash; value["flac"] = flac
            let stream = try XCTUnwrap(SourceResolver.biliAudio(in: value, quality: .hires))
            XCTAssertTrue(stream.url.hasSuffix("high"))
            XCTAssertEqual(stream.quality, "高音质")
        }
    }

    func testMissingRequestedTierUsesLowestAvailableAndSkipsBadURLs() throws {
        var value = dash
        value["audio"] = [["id": 30280, "baseUrl": "https://example.com/only"]]
        XCTAssertTrue(try XCTUnwrap(SourceResolver.biliAudio(in: value, quality: .low)).url.hasSuffix("only"))
        value["audio"] = [["id": 30280, "baseUrl": ""], ["id": 30232, "baseUrl": "https://example.com/ok"]]
        XCTAssertTrue(try XCTUnwrap(SourceResolver.biliAudio(in: value, quality: .high)).url.hasSuffix("ok"))
        XCTAssertNil(SourceResolver.biliAudio(in: [:], quality: .high))
    }
}
