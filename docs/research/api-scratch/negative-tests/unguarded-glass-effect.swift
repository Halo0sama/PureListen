// NEGATIVE TEST — must FAIL when compiled with a macOS < 26 deployment target.
// Proves that `.glassEffect` cannot be used while `platforms: [.macOS(.v13)]`.
// Reproduce:
//   xcrun swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
//     -target arm64-apple-macosx13.0 negative-tests/unguarded-glass-effect.swift
import SwiftUI

struct Card: View {
    var body: some View {
        Text("hi").padding().glassEffect(in: .rect(cornerRadius: 12))
    }
}
