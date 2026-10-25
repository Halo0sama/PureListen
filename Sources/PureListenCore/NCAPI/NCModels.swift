import Foundation

public struct NCProfile: Codable, Equatable {
    public var userId: Int
    public var nickname: String
    public var avatarUrl: String

    public init?(json: [String: Any]) {
        guard let id = json["userId"] as? Int else { return nil }
        self.userId = id
        self.nickname = json["nickname"] as? String ?? "网易云用户"
        self.avatarUrl = json["avatarUrl"] as? String ?? ""
    }
}

public struct NCPlaylist: Codable, Identifiable, Equatable {
    public var id: Int
    public var name: String
    public var coverUrl: String
    public var trackCount: Int
    public var playCount: Int64

    public init(id: Int, name: String, coverUrl: String, trackCount: Int, playCount: Int64) {
        self.id = id; self.name = name; self.coverUrl = coverUrl
        self.trackCount = trackCount; self.playCount = playCount
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        self.name = (json["name"] as? String) ?? "未命名歌单"
        let cover = (json["coverImgUrl"] as? String) ?? (json["picUrl"] as? String) ?? ""
        self.coverUrl = cover
        self.trackCount = (json["trackCount"] as? Int) ?? 0
        if let pc = json["playCount"] as? Int { self.playCount = Int64(pc) }
        else if let pc = json["playCount"] as? Double { self.playCount = Int64(pc) }
        else { self.playCount = 0 }
    }
}

public struct NCTrack: Codable, Identifiable, Equatable {
    public var id: Int
    public var name: String
    public var artists: String
    public var album: String
    public var durationMs: Int
    public var vipOnly: Bool
    public var coverURL: String

    public init(id: Int, name: String, artists: String, album: String, durationMs: Int,
                vipOnly: Bool, coverURL: String = "") {
        self.id = id; self.name = name; self.artists = artists; self.album = album
        self.durationMs = durationMs; self.vipOnly = vipOnly; self.coverURL = coverURL
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        self.name = (json["name"] as? String) ?? "未知曲目"
        if let ar = json["ar"] as? [[String: Any]] {
            self.artists = ar.compactMap { $0["name"] as? String }.joined(separator: " / ")
        } else if let ar = json["artists"] as? [[String: Any]] {
            self.artists = ar.compactMap { $0["name"] as? String }.joined(separator: " / ")
        } else {
            self.artists = "未知歌手"
        }
        var cover = ""
        if let al = json["al"] as? [String: Any] {
            self.album = (al["name"] as? String) ?? ""
            cover = (al["picUrl"] as? String) ?? ""
        } else if let al = json["album"] as? [String: Any] {
            self.album = (al["name"] as? String) ?? ""
            if let pic = al["picUrl"] as? String { cover = pic }
            else if let picObj = al["pic"] as? [String: Any] { cover = (picObj["url"] as? String) ?? "" }
        } else {
            self.album = ""
        }
        self.coverURL = cover
        self.durationMs = (json["dt"] as? Int) ?? (json["duration"] as? Int) ?? 0
        let fee = (json["fee"] as? Int) ?? 0
        self.vipOnly = fee == 1 || (json["copyright"] as? Int) == 0
    }
}

/// 取到的音频直链信息。
public struct NCSongURL: Codable {
    public var url: String?
    public var format: String       // flac / mp3 / ...
    public var level: String        // standard / lossless / hires ...
    public var sizeBytes: Int64
    public var br: Int              // 码率 kbps
    public var fee: Int
    public var freeTrialInfo: String?

    init?(json: [String: Any]) {
        self.url = json["url"] as? String
        self.format = (json["type"] as? String) ?? ""
        self.level = (json["level"] as? String) ?? ""
        if let s = json["size"] as? Int { self.sizeBytes = Int64(s) }
        else if let s = json["size"] as? Double { self.sizeBytes = Int64(s) }
        else { self.sizeBytes = 0 }
        self.br = (json["br"] as? Int) ?? 0
        self.fee = (json["fee"] as? Int) ?? 0
        if let trial = json["freeTrialInfo"], let t = trial as? [String: Any] {
            self.freeTrialInfo = "试听片段 (\(t["start"] ?? 0)-\(t["end"] ?? 0)s)"
        } else {
            self.freeTrialInfo = nil
        }
        if url == nil && format.isEmpty { return nil }
    }
}

public enum NCLevel: String, CaseIterable, Codable {
    case lossless
    case hires
    case exhigh
    case standard

    public var label: String {
        switch self {
        case .lossless: return "无损 FLAC"
        case .hires: return "Hi-Res 母带"
        case .exhigh: return "极高 320k"
        case .standard: return "标准 128k"
        }
    }
}
