// NEGATIVE TEST — must FAIL at macOS < 15 because
// ContainerBackgroundPlacement.window is macOS 15.0+.
import SwiftUI

struct Content: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            Text("hi").containerBackground(.thickMaterial, for: .window)
        } else {
            Text("hi")
        }
    }
}
