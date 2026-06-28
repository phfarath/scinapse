// SciNapse/Sources/Sharing/PDFExporter.swift
import SwiftUI
import UIKit

enum PDFExporter {
    @MainActor
    static func pdf(from view: some View, pageSize: CGSize) -> Data {
        let renderer = ImageRenderer(content:
            view.frame(width: pageSize.width, alignment: .topLeading)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2.0
        var data = Data()
        renderer.render { size, renderInContext in
            var box = CGRect(
                origin: .zero,
                size: CGSize(width: pageSize.width, height: max(size.height, pageSize.height))
            )
            let mutableData = CFDataCreateMutable(nil, 0)!
            guard let consumer = CGDataConsumer(data: mutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            data = mutableData as Data
        }
        return data
    }

    static func writeTempPDF(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
    }
}
