// SciNapseKit/Sources/SciNapseKit/Common/Config.swift
import Foundation

public enum Config {
    /// Deve ser um e-mail real: o Unpaywall rejeita placeholders (HTTP 422).
    public static var contactEmail = "pedropontesfarath@gmail.com"
    public static var userAgent: String { "SciNapse/1.0 (mailto:\(contactEmail))" }
    /// Opcional (Fase 1.5). Desligado por padrão — OpenAlex exige key desde fev/2026.
    public static var openAlexAPIKey: String? = nil
    public static let pubmedTool = "SciNapse"
}
