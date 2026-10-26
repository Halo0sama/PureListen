import Foundation

public enum BiliAudioQuality: String, CaseIterable {
    case hires, high, standard, low

    public var label: String {
        switch self {
        case .hires: return "Hi-Res"
        case .high: return "高音质"
        case .standard: return "标准"
        case .low: return "省流"
        }
    }
}

extension SourceResolver {
    struct BiliAudioStream {
        var url: String
        var quality: String
        var bitrate: Int
        var codec: String
    }

    static func biliAudio(in dash: [String: Any], quality: BiliAudioQuality) -> BiliAudioStream? {
        func stream(_ raw: [String: Any], label: String) -> BiliAudioStream? {
            let url = (raw["baseUrl"] as? String) ?? (raw["base_url"] as? String) ?? ""
            guard !url.isEmpty else { return nil }
            return BiliAudioStream(url: url, quality: label,
                                   bitrate: (raw["bandwidth"] as? Int) ?? 0,
                                   codec: (raw["codecs"] as? String) ?? "")
        }
        if quality == .hires,
           let flac = dash["flac"] as? [String: Any],
           let audio = flac["audio"] as? [String: Any],
           let result = stream(audio, label: "Hi-Res") { return result }

        let audio = (dash["audio"] as? [[String: Any]]) ?? []
        let ceiling: Int
        switch quality {
        case .hires, .high: ceiling = 30280
        case .standard: ceiling = 30232
        case .low: ceiling = 30216
        }
        // id 是档位标识；不能把杜比等不同编码的 id 当成更高码率。
        let normal = audio.filter { [30216, 30232, 30280].contains($0["id"] as? Int ?? 0) }
        let candidates = normal.filter { ($0["id"] as? Int ?? 0) <= ceiling }
            .sorted { ($0["id"] as? Int ?? 0) > ($1["id"] as? Int ?? 0) }
        let fallback = normal.sorted { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
        for raw in candidates + fallback {
            let label: String
            switch raw["id"] as? Int {
            case 30280: label = "高音质"
            case 30232: label = "标准"
            default: label = "省流"
            }
            if let result = stream(raw, label: label) { return result }
        }
        return nil
    }
}
