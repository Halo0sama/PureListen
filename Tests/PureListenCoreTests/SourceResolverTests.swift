import XCTest
@testable import PureListenCore

final class SourceResolverTests: XCTestCase {
    func testNeteaseLinksAndShareText() {
        for input in ["12345", "https://music.163.com/song?id=12345",
                      "https://music.163.com/#/song?id=12345&userid=9",
                      "分享歌曲 https://music.163.com/song?id=12345 （来自网易云音乐）"] {
            XCTAssertEqual(SourceResolver.classify(input)?.kind, "netease", input)
            XCTAssertEqual(SourceResolver.classify(input)?.value, "12345", input)
        }
    }

    func testBilibiliIdentifiersAndLinks() {
        for input in ["BV1xx411c7mD", "av170001", "AV170001", "分享 BV1xx411c7mD",
                      "https://www.bilibili.com/video/BV1xx411c7mD/?p=2", "https://b23.tv/example"] {
            XCTAssertEqual(SourceResolver.classify(input)?.kind, "bilibili", input)
        }
        XCTAssertEqual(SourceResolver.bilibiliIdentifier(in: "/video/BV1xx411c7mD/"), "BV1xx411c7mD")
        XCTAssertEqual(SourceResolver.bilibiliIdentifier(in: "/video/AV170001"), "av170001")
        XCTAssertNil(SourceResolver.classify("BVbad"))
        XCTAssertNil(SourceResolver.classify("av0"))
        XCTAssertNil(SourceResolver.bilibiliIdentifier(in: "BV1xx411c7mDextra"))
    }

    func testOnlyRealHostsAndAudioPathsAreClassified() {
        for input in ["https://music.163.com.evil.example/song?id=12345",
                      "https://evil.example/bilibili.com/video/BV1xx411c7mD",
                      "https://example.com/download?name=song.mp3",
                      "https://music.163.com/playlist?id=123", "file:///tmp/song.flac", "-1"] {
            XCTAssertNil(SourceResolver.classify(input), input)
        }
        XCTAssertEqual(SourceResolver.classify("HTTPS://example.com/A.FLAC?token=1")?.kind, "direct")
    }

    func testDirectMetadataExcludesQueryAndUsesPathExtension() {
        let item = SourceResolver.resolveDirect("https://example.com/%E6%B5%8B%E8%AF%95.FLAC?token=other.mp3")
        XCTAssertEqual(item.title, "测试.FLAC")
        XCTAssertEqual(item.format, "flac")
        XCTAssertEqual(item.downloadURL, "https://example.com/%E6%B5%8B%E8%AF%95.FLAC?token=other.mp3")
    }
}
