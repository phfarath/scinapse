import SwiftUI
import SciNapseKit

struct ShareSourceBadge: View {
    let tier: TrustTier
    let retraction: RetractionStatus
    var body: some View {
        HStack(spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
            if retraction != .none {
                Label("Retratado", systemImage: "xmark.octagon.fill")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.15), in: Capsule()).foregroundStyle(.red)
            }
        }
    }
    private var label: String { tier == .verified ? "Verificada" : tier == .recognized ? "Reconhecida" : "Não verificada" }
    private var symbol: String { tier == .verified ? "checkmark.seal.fill" : tier == .recognized ? "checkmark.shield" : "exclamationmark.triangle" }
    private var color: Color { tier == .verified ? .green : tier == .recognized ? .blue : .orange }
}
