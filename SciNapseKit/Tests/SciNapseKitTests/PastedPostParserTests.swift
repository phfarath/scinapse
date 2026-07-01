// SciNapseKit/Tests/SciNapseKitTests/PastedPostParserTests.swift
import XCTest
@testable import SciNapseKit

final class PastedPostParserTests: XCTestCase {

    // Texto real colado pelo usuário (saída do ChatGPT), com o preâmbulo de chat,
    // 1 título geral, 5 achados numerados e a seção "O que muda na prática".
    private let sample = """
    Pronto — fiz a atualização e criei um rascunho no Gmail, sem destinatário e sem enviar.

    Atualização semanal em Anestesiologia — 28/06/2026

    1. Anemia pré-operatória e risco pós-operatório: sinal mais forte em mulheres

    Fonte: British Journal of Anaesthesia — BJA
    Tipo de estudo/publicação: Coorte observacional retrospectiva, online ahead of print
    Resumo: Estudo recente do BJA avaliou grande base perioperatória e encontrou associação entre anemia pré-operatória e piores desfechos pós-operatórios; o sinal pareceu mais forte em mulheres. O artigo foi publicado online em 09/06/2026.
    Por que importa: Reforça a necessidade de rastrear e otimizar anemia antes de cirurgias eletivas.
    Limitações/cautelas: Estudo observacional; não prova causalidade.
    Link/referência: Crispell EH et al. Br J Anaesth. 2026. DOI: 10.1016/j.bja.2026.04.052.

    2. Bloqueios fasciais guiados por ultrassom em fraturas de costelas

    Fonte: BMC Anesthesiology
    Tipo de estudo/publicação: Revisão sistemática e meta-análise
    Resumo: Revisão com 9 ensaios randomizados e 664 pacientes avaliou bloqueios fasciais guiados por ultrassom, com SMD −0,44, sem alteração relevante de PaO₂/PaCO₂.
    Por que importa: Analgesia eficaz em fratura de costelas é central para evitar hipoventilação.
    Limitações/cautelas: Evidência de baixa ou muito baixa certeza.
    Link/referência: Ge Y et al. BMC Anesthesiology. Published 24 Jun 2026. DOI: 10.1186/s12871-026-04045-x.

    3. Morfina intratecal em baixa dose versus fentanil intratecal na cesárea

    Fonte: BMC Anesthesiology
    Tipo de estudo/publicação: Ensaio clínico randomizado pragmático
    Resumo: Ensaio randomizado em cesárea comparou morfina intratecal 100 mcg, morfina intratecal 50 mcg e fentanil intratecal 25 mcg.
    Por que importa: Dá suporte prático ao uso de morfina intratecal em baixa dose.
    Limitações/cautelas: Estudo unicêntrico, com amostra pequena.
    Link/referência: Chetty S, Paruk F, Kamerman P. BMC Anesthesiology. Published 23 Jun 2026. DOI: 10.1186/s12871-026-04034-0.

    4. PEEP guiada por driving pressure em cirurgia bariátrica laparoscópica

    Fonte: BMC Anesthesiology
    Tipo de estudo/publicação: Ensaio clínico randomizado de superioridade
    Resumo: Estudo brasileiro randomizou pacientes obesos em cirurgia bariátrica laparoscópica; a estratégia guiada por driving pressure reduziu a incidência de driving pressure elevada.
    Por que importa: Reforça a individualização da ventilação protetora em pacientes obesos.
    Limitações/cautelas: Estudo unicêntrico com 78 pacientes.
    Link/referência: Silveira SQ et al. BMC Anesthesiology. Published 13 Jun 2026. DOI: 10.1186/s12871-026-04026-0.

    5. Anestesia livre de opioides em VATS: menos PONV e possível redução de dor crônica

    Fonte: BMC Anesthesiology
    Tipo de estudo/publicação: Revisão sistemática e meta-análise de ensaios randomizados
    Resumo: Meta-análise de 10 RCTs, com 1.106 pacientes submetidos a cirurgia torácica videoassistida.
    Por que importa: Pode orientar protocolos ERAS torácicos.
    Limitações/cautelas: Protocolos de anestesia livre de opioides variam bastante.
    Link/referência: Yang J et al. BMC Anesthesiology. Published 16 Jun 2026. DOI: 10.1186/s12871-026-04028-y.

    O que muda na prática?

    * Em cirurgias eletivas, anemia pré-operatória deve ser rastreada e tratada com mais rigor.
    * Em fraturas de costelas, bloqueios fasciais guiados por ultrassom são opção promissora.
    """

    // MARK: - Título

    func test_title_isFirstHeadingAfterChatter() {
        let draft = PastedPostParser.parse(sample)
        XCTAssertEqual(draft.title, "Atualização semanal em Anestesiologia — 28/06/2026")
    }

    func test_body_dropsChatterAndTitle() {
        let draft = PastedPostParser.parse(sample)
        XCTAssertFalse(draft.body.contains("rascunho no Gmail"), "preâmbulo de chat deveria sair")
        XCTAssertFalse(draft.body.contains("Atualização semanal em Anestesiologia"), "título não deve duplicar no corpo")
    }

    func test_body_dropsReferenceLines() {
        let draft = PastedPostParser.parse(sample)
        XCTAssertFalse(draft.body.contains("Link/referência"), "linhas de referência viram Fontes")
        XCTAssertFalse(draft.body.contains("10.1016/j.bja"), "nenhum DOI deve sobrar no corpo")
        XCTAssertFalse(draft.body.contains("10.1186/s12871"), "nenhum DOI deve sobrar no corpo")
    }

    func test_body_keepsItemContent() {
        let draft = PastedPostParser.parse(sample)
        XCTAssertTrue(draft.body.contains("1. Anemia pré-operatória"))
        XCTAssertTrue(draft.body.contains("Fonte: British Journal of Anaesthesia"), "linha Fonte: fica como contexto")
        XCTAssertTrue(draft.body.contains("Resumo: Estudo recente do BJA"))
        XCTAssertTrue(draft.body.contains("O que muda na prática?"))
    }

    func test_body_doesNotStartBlank() {
        let draft = PastedPostParser.parse(sample)
        XCTAssertTrue(draft.body.hasPrefix("1. Anemia pré-operatória"), "corpo começa direto no conteúdo")
    }

    // MARK: - Detecção / Fontes

    func test_looksStructured_trueForMultiSource() {
        XCTAssertTrue(PastedPostParser.looksStructured(sample))
    }

    func test_looksStructured_falseForPlainText() {
        XCTAssertFalse(PastedPostParser.looksStructured("Só um rascunho rápido sobre a conferência de amanhã."))
        XCTAssertFalse(PastedPostParser.looksStructured("Um único DOI: 10.1016/j.bja.2026.04.052"), "1 identificador não é lote")
    }

    func test_extractAllInProse_findsExactlyFiveDOIs_noBareNumbers() {
        // A prosa tem números soltos (9, 664, 24h, 100 mcg, 78 pacientes...) que
        // NÃO podem virar PMIDs. Só os 5 DOIs devem sair.
        let ids = IdentifierParser.extractAllInProse(in: sample)
        XCTAssertEqual(ids.count, 5)
        XCTAssertEqual(ids, [
            "10.1016/j.bja.2026.04.052",
            "10.1186/s12871-026-04045-x",
            "10.1186/s12871-026-04034-0",
            "10.1186/s12871-026-04026-0",
            "10.1186/s12871-026-04028-y",
        ])
    }

    // MARK: - Formato sem preâmbulo

    func test_parse_noChatter_titleIsFirstLine() {
        let text = """
        Título direto sem preâmbulo
        Resumo: conteúdo qualquer aqui.
        Link/referência: Autor X. DOI: 10.1000/abc123
        """
        let draft = PastedPostParser.parse(text)
        XCTAssertEqual(draft.title, "Título direto sem preâmbulo")
        XCTAssertTrue(draft.body.contains("Resumo: conteúdo qualquer"))
        XCTAssertFalse(draft.body.contains("10.1000/abc123"))
    }
}
