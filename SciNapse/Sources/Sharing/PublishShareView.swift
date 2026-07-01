// SciNapse/Sources/Sharing/PublishShareView.swift
// Sheet de compartilhamento de uma página publicada: QR + copiar + share com texto pronto.
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum QRCode {
    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct PublishShareView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false
    @State private var copied = false

    private var shareText: String { "\(title) — publicado no SciNapse:\n\(url.absoluteString)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let qr = QRCode.image(from: url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 210, height: 210)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
                }
                Text(url.absoluteString)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .padding(.horizontal)

                Button {
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation { copied = true }
                } label: {
                    Label(copied ? "Copiado!" : "Copiar link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button { showSystemShare = true } label: {
                    Label("Compartilhar", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.blue)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Compartilhar página")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
            .sheet(isPresented: $showSystemShare) { ShareSheet(activityItems: [shareText]) }
        }
    }
}
