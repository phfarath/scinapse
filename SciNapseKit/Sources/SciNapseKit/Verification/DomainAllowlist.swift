// SciNapseKit/Sources/SciNapseKit/Verification/DomainAllowlist.swift
import Foundation

public enum DomainAllowlist {
    public static let domains: Set<String> = [
        // Órgãos
        "nih.gov", "ncbi.nlm.nih.gov", "cdc.gov", "fda.gov", "who.int", "paho.org",
        "ema.europa.eu", "ecdc.europa.eu", "anvisa.gov.br", "saude.gov.br", "fiocruz.br",
        "scielo.br", "clinicaltrials.gov", "cochranelibrary.com", "europepmc.org",
        // Preprints / repositórios
        "medrxiv.org", "biorxiv.org", "arxiv.org", "researchsquare.com", "ssrn.com",
        "osf.io", "zenodo.org", "figshare.com",
        // Periódicos / editoras
        "nejm.org", "thelancet.com", "bmj.com", "jamanetwork.com", "nature.com",
        "science.org", "cell.com", "pnas.org", "springer.com", "link.springer.com",
        "wiley.com", "onlinelibrary.wiley.com", "sciencedirect.com", "academic.oup.com",
        "karger.com", "tandfonline.com", "mdpi.com", "frontiersin.org", "plos.org",
        "elifesciences.org",
        // Sociedades
        "ahajournals.org", "diabetesjournals.org", "atsjournals.org", "acpjournals.org",
        "annals.org", "ascopubs.org", "endocrine.org", "jci.org"
    ]

    public static func isRecognized(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
