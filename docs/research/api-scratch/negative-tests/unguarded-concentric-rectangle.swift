// NEGATIVE TEST — must FAIL at macOS < 26.
import SwiftUI

struct Card: View {
    var body: some View {
        Text("hi").clipShape(ConcentricRectangle(corners: .concentric))
    }
}
