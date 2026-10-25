// NEGATIVE TEST — must FAIL on macOS at any deployment: `.navigation` is
// explicitly unavailable on macOS (only `.window` exists on macOS).
import SwiftUI

struct Content: View {
    var body: some View {
        Text("hi").containerBackground(.regularMaterial, for: .navigation)
    }
}
