import Foundation

enum PlaybackMode: String, CaseIterable {
    case sequential, repeatAll, repeatOne, shuffle

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatAll: return "列表循环"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }
    var symbol: String {
        switch self {
        case .sequential: return "list.bullet"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
    var next: Self {
        let modes = Self.allCases
        return modes[(modes.firstIndex(of: self)! + 1) % modes.count]
    }
}

struct ShuffleNavigation {
    private var remaining: [Int] = []
    private var history: [Int] = []
    private var cursor = 0
    var shuffle: ([Int]) -> [Int] = { $0.shuffled() }

    mutating func reset(count: Int, current: Int) {
        remaining = shuffle(Array(0..<count).filter { $0 != current })
        history = (0..<count).contains(current) ? [current] : []
        cursor = 0
    }
    var upcoming: Int? {
        if cursor + 1 < history.count { return history[cursor + 1] }
        return remaining.first
    }
    mutating func next(count: Int, current: Int) -> Int? {
        guard count > 0 else { return nil }
        if cursor + 1 < history.count { cursor += 1; return history[cursor] }
        if remaining.isEmpty { remaining = shuffle(Array(0..<count).filter { $0 != current }) }
        let selected = remaining.isEmpty ? 0 : remaining.removeFirst()
        history.append(selected)
        if history.count > 512 { history.removeFirst() }
        cursor = history.count - 1
        return selected
    }
    mutating func previous(current: Int) -> Int {
        guard cursor > 0 else { return current }
        cursor -= 1
        return history[cursor]
    }
}
