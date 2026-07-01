// SciNapseKit/Sources/SciNapseKit/Common/Config.swift
import Foundation

public enum Config {
    /// Deve ser um e-mail real: o Unpaywall rejeita placeholders (HTTP 422).
    public static var contactEmail = "pedropontesfarath@gmail.com"
    public static let appGroupID = "group.com.phfarath.scinapse"
    public static var userAgent: String { "SciNapse/1.0 (mailto:\(contactEmail))" }
    /// Opcional (Fase 1.5). Desligado por padrão — OpenAlex exige key desde fev/2026.
    public static var openAlexAPIKey: String? = nil
    public static let pubmedTool = "SciNapse"

    // MARK: - Fase 2a (publicação web)
    /// Projeto Supabase do SciNapse (conta própria; ver memória do projeto).
    public static let supabaseURL = "https://gbkknpzayiqrknebzoxr.supabase.co"
    /// anon key — pública por design (a RLS bloqueia escrita).
    public static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdia2tucHpheWlxcmtuZWJ6b3hyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MDA1NTcsImV4cCI6MjA5ODM3NjU1N30.soxOemB1vvBLBkijYQ4-MtmuvOoayEyQUfbU7pza5gQ"
    /// Barreira fraca de publicação (Fase 2a): trocada por Auth no 2b. NÃO é segredo forte.
    /// Lido do Info.plist (chave `PublishSecret`), injetado por `Secrets.xcconfig` (gitignored) em build.
    public static var publishSecret: String {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "PublishSecret") as? String,
              !s.isEmpty, !s.hasPrefix("$(") else { return "" }
        return s
    }
    /// Base da página leitora (GitHub Pages). URL final = readerBaseURL + "#" + slug.
    public static let readerBaseURL = "https://phfarath.github.io/scinapse/"
}
