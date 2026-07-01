// SciNapseKit/Sources/SciNapseKit/Composing/PastedPostParser.swift
import Foundation

/// Resultado de separar um bloco colado (ex.: uma "atualização semanal" gerada
/// por IA) nos campos do compositor de post: Título + Síntese.
/// Os identificadores (DOIs/PMIDs/URLs) ficam por conta de
/// `IdentifierParser.extractAll`, que vira as Fontes.
public struct PastedPostDraft: Equatable {
    public let title: String
    public let body: String
    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Separa um texto colado em Título + Síntese. Puro (sem rede, sem SwiftData)
/// para ser testável isoladamente.
public enum PastedPostParser {
    /// Heurística barata para decidir se vale oferecer "separar": true quando o
    /// texto traz 2+ identificadores (cenário de lote com várias fontes).
    public static func looksStructured(_ raw: String) -> Bool {
        IdentifierParser.extractAllInProse(in: raw).count >= 2
    }

    public static func parse(_ raw: String) -> PastedPostDraft {
        let lines = raw.components(separatedBy: .newlines)
        let titleIndex = titleLineIndex(in: lines)
        let title = titleIndex.map { lines[$0].trimmingCharacters(in: .whitespaces) } ?? ""

        // Corpo = tudo depois do título, sem as linhas de referência
        // (elas viram Fontes) e sem espaços em branco excedentes.
        let start = (titleIndex ?? -1) + 1
        let bodyLines = start < lines.count
            ? lines[start...].filter { !isReferenceLine($0) }
            : ArraySlice<String>()
        let body = collapseBlankLines(Array(bodyLines))
        return PastedPostDraft(title: title, body: body)
    }

    // MARK: - Título

    /// Índice da primeira linha "cabeçalho" (curta, sem pontuação final de frase,
    /// não é campo/referência). Pula preâmbulo/chatter que termina em ponto.
    private static func titleLineIndex(in lines: [String]) -> Int? {
        var considered = 0
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if isLikelyTitle(t) { return i }
            considered += 1
            if considered >= 8 { break }
        }
        // Fallback: primeira linha não-vazia.
        return lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func isLikelyTitle(_ t: String) -> Bool {
        guard t.count <= 120 else { return false }
        if let last = t.last, ".!?".contains(last) { return false } // frase inteira / chatter
        if isFieldLine(t) || isReferenceLine(t) { return false }
        return true
    }

    // MARK: - Linhas de campo / referência

    private static let fieldPrefixes = [
        "fonte:", "fonte ", "tipo de estudo", "tipo:", "resumo:", "resumo ",
        "por que importa", "limitações", "limitacoes", "conclusão", "conclusao"
    ]
    /// Linha rotulada dentro de um item (Fonte:, Resumo:, ...). Não vira título,
    /// mas permanece no corpo como conteúdo.
    private static func isFieldLine(_ t: String) -> Bool {
        let l = t.lowercased()
        return fieldPrefixes.contains { l.hasPrefix($0) }
    }

    private static let referencePrefixes = [
        "link/refer", "link:", "referência", "referencia", "doi:", "doi "
    ]
    /// Linha que é (ou contém) a referência bibliográfica — vira Fonte e some do
    /// corpo para não duplicar.
    private static func isReferenceLine(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if IdentifierParser.extractDOI(in: t) != nil { return true }
        if IdentifierParser.extractPMID(in: t) != nil { return true }
        let l = t.lowercased()
        return referencePrefixes.contains { l.hasPrefix($0) }
    }

    // MARK: - Utilidades

    /// Junta as linhas colapsando múltiplas linhas em branco em uma só e
    /// removendo brancos no início/fim.
    private static func collapseBlankLines(_ lines: [String]) -> String {
        var out: [String] = []
        var blanks = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                if blanks > 1 || out.isEmpty { continue }
                out.append("")
            } else {
                blanks = 0
                out.append(line)
            }
        }
        while let last = out.last, last.isEmpty { out.removeLast() }
        return out.joined(separator: "\n")
    }
}
