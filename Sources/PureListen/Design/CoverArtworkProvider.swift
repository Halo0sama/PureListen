import AppKit

/// 封面图的本地来源钩子。
///
/// 线上运行时保持 `nil`; Debug 截图模式(`UIPreviewStudio`)会注入程序化生成的抽象封面,
/// 让截图与 Xcode Preview 不必联网也能呈现完整的视觉。
@MainActor
enum CoverArtworkProvider {
    static var provider: ((String, CGFloat) -> NSImage?)?
}
