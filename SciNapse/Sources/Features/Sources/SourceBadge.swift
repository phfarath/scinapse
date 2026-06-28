// SciNapse/Sources/Features/Sources/SourceBadge.swift
import SwiftUI
import SciNapseKit

enum BadgeStyle {
    static func label(_ tier: TrustTier) -> String {
        switch tier {
        case .verified: return "Verificada"
        case .recognized: return "Reconhecida"
        case .unverified: return "Não verificada"
        }
    }
    static func symbol(_ tier: TrustTier) -> String {
        switch tier {
        case .verified: return "checkmark.seal.fill"
        case .recognized: return "checkmark.shield"
        case .unverified: return "exclamationmark.triangle"
        }
    }
    static func color(_ tier: TrustTier) -> Color {
        switch tier {
        case .verified: return .green
        case .recognized: return .blue
        case .unverified: return .orange
        }
    }
}

struct SourceBadge: View {
    let tier: TrustTier
    let retraction: RetractionStatus

    var body: some View {
        HStack(spacing: 6) {
            Label(BadgeStyle.label(tier), systemImage: BadgeStyle.symbol(tier))
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                .background(BadgeStyle.color(tier).opacity(0.15), in: Capsule())
                .foregroundStyle(BadgeStyle.color(tier))
            if retraction != .none {
                Label(retractionText, systemImage: "xmark.octagon.fill")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.15), in: Capsule())
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("retractionBadge")
            }
        }
    }

    private var retractionText: String {
        switch retraction {
        case .retracted: return "Retratado"
        case .concern: return "Com ressalva"
        case .correction: return "Corrigido"
        case .none: return ""
        }
    }
}
