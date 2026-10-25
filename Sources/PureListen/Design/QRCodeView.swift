import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// 统一二维码组件: 白色卡片 + 柔和投影 + 可选"已确认"浮层。
struct QRCodeView: View {
    var content: String
    var size: CGFloat = 176
    /// 已扫码: 压暗并浮出对勾。
    var scanned: Bool = false
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            if let image = Self.qrImage(from: content) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .opacity(scanned ? 0.22 : 1)
            } else {
                ProgressView()
            }
            if scanned {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                    Text("已确认")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .animation(DS.Motion.standard, value: scanned)
    }

    static func qrImage(from string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage,
                       size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
