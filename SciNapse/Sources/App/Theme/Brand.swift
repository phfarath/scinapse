// SciNapse/Sources/App/Theme/Brand.swift
import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Paleta da marca SciNapse, extraída do logo (lupa + S, gradiente azul → teal).
enum Brand {
    static let blue = Color(hex: 0x1267EA)       // azul primário
    static let blueDeep = Color(hex: 0x0642B5)   // azul profundo
    static let teal = Color(hex: 0x14D7B1)       // teal
    static let tealDeep = Color(hex: 0x007A78)   // verde-escuro

    /// Gradiente diagonal da marca (azul → teal), usado em headers e no wordmark.
    static let gradient = LinearGradient(
        colors: [blue, blueDeep, teal, tealDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Wordmark "SciNapse" com o gradiente da marca. Usado no cabeçalho da tela principal.
struct SciNapseWordmark: View {
    var size: CGFloat = 22
    var body: some View {
        Text("SciNapse")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(Brand.gradient)
            .accessibilityIdentifier("scinapseWordmark")
    }
}
