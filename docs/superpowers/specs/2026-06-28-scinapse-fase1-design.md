# SciNapse — Spec de Design (Fase 1: device-only)

- **Data:** 2026-06-28
- **Status:** Aprovado para escrita de plano de implementação
- **Plataforma:** iOS (iOS-only), nativo
- **Stack:** Swift 6 / SwiftUI / SwiftData, sem dependências externas (apenas `URLSession` + `Codable`)
- **Deployment target:** iOS 17.4

---

## 1. Visão e tese

SciNapse é um app onde um profissional de saúde **sintetiza um achado científico e é obrigado a ancorá-lo em fontes verificáveis**. O app faz a verificação **algoritmicamente, sem IA**, e transforma a síntese + as fontes numa **página limpa e citável**.

A barreira anti-fake-news **não é moderação humana nem IA**: é **estrutural**.

1. **Sem fonte → não publica.** Todo post exige ≥1 fonte.
2. **Fonte fraca → selo visível.** Cada fonte recebe uma camada de confiança (Verificada / Reconhecida / Não verificada) e, ortogonalmente, um **alerta de retratação** quando aplicável.

A motivação original (do idealizador, médico): salvar e compartilhar com residentes/colegas as principais publicações da semana sobre um tópico, sem propagar desinformação.

### Por que isso funciona sem IA

Identificadores científicos (DOI, PMID) são resolvíveis em APIs públicas e gratuitas que devolvem metadados estruturados e, crucialmente, **sinais de retratação** (Crossref + Retraction Watch). Ancorar o produto nesses identificadores entrega, de graça:

- página montada sozinha (metadados → layout),
- referência formatada (Vancouver) automática,
- selo de credibilidade por construção,
- detecção de artigos retratados que continuam circulando — o sinal anti-desinformação mais forte que existe em medicina.

---

## 2. Escopo da Fase 1

### Dentro do escopo (MVP device-only, 1 usuário, sem backend)

- Tópicos (CRUD local).
- Adicionar fonte por **DOI / PMID / URL**, com verificação online (APIs públicas) e classificação em camadas.
- **Detecção automática de retratação / errata / expressão de preocupação.**
- Criar **post autoral** (título + corpo) com **gate de publicação: ≥1 fonte**.
- **Salvar artigo** (fonte solta, sem post).
- **Página do post** (a "página" gerada): síntese + fontes com badges + referência Vancouver.
- **Digest semanal** por tópico: agrega posts dos últimos 7 dias numa página exportável.
- **Compartilhar/exportar** post ou digest via Share Sheet do iOS (texto + PDF) — valida a dor original sem backend.
- Funcionamento **offline-first**: criar tópicos/posts/rascunhos sem rede; fontes ficam "pendentes de verificação" e re-verificam quando online.

### Fora do escopo agora (YAGNI)

- Contas/login, backend, sincronização, feed social, comentários, seguidores.
- Notificações push, Android, web.
- IA / sumarização / tradução automática.
- Armazenamento de PDFs de artigos.
- Busca textual no PubMed dentro do app (só resolução por identificador/URL).

### Fast-follow (Fase 1.5, fora deste spec)

- **Share Extension**: compartilhar do Safari/PubMed/Mail direto pro SciNapse (novo target + App Group).
- Chave OpenAlex opcional como enriquecimento (abstract + cross-check de retratação).

---

## 3. Fluxos principais (user stories)

1. **Salvar um artigo num tópico.** Usuário abre tópico → "Salvar artigo" → cola DOI/PMID/URL → app verifica e mostra preview (título, autores, journal, ano, badge de camada, alerta de retratação se houver) → confirma → artigo salvo no tópico.
2. **Publicar um achado.** Usuário abre tópico → "Novo post" → escreve título + corpo → anexa ≥1 fonte (mesma sheet de verificação) → "Publicar" (bloqueado se 0 fontes) → post publicado.
3. **Ler a página.** Usuário toca num post → vê a página: cabeçalho, síntese, lista de fontes com badges + referências Vancouver → pode compartilhar (texto + PDF).
4. **Compartilhar o resumo da semana.** Usuário abre tópico → "Gerar digest da semana" → app agrega os posts dos últimos 7 dias → página de digest → "Compartilhar" → Share Sheet (WhatsApp/Mail) com texto + PDF.

---

## 4. Arquitetura geral

App de camada única no device, sem servidor. Camadas lógicas:

```
UI (SwiftUI Views)
        │  @Query / ações
        ▼
Persistência (SwiftData: ModelContainer, @ModelActor SourceFetcher)
        │
        ▼
Verificação (rede → classificação → formatação)   ──►  APIs públicas (Crossref, Unpaywall, PubMed, doi.org)
```

### Organização de pastas (leaf nodes, arquivos focados)

```
SciNapse/
  App/                 ScinapseApp.swift, ContentView.swift
  Models/              Topic.swift, Post.swift, Source.swift, Enums.swift, SchemaV1.swift
  Persistence/         ModelContainer+Setup.swift, SourceFetcher.swift  (@ModelActor)
  Verification/
    IdentifierParser.swift        (DOI/PMID/URL → tipo)
    MetadataService.swift         (orquestra o pipeline)
    CrossrefClient.swift          (primário: metadados + retratação)
    UnpaywallClient.swift         (open access)
    PubMedClient.swift            (PMID → DOI via PMC ID Converter; efetch p/ abstract)
    HTMLDoiExtractor.swift        (meta tags / JSON-LD de páginas)
    DomainAllowlist.swift         (classificação "Reconhecida")
    TrustClassifier.swift         (decide a camada + retraction)
    VancouverFormatter.swift      (metadados → string Vancouver)
    AbstractReconstructor.swift   (inverted index → texto; só se usar OpenAlex)
  Features/
    Topics/            TopicListView.swift, TopicDetailView.swift
    Posts/             ComposePostView.swift, PostDetailView.swift
    Sources/           AddSourceSheet.swift, SourcePreviewView.swift, SourceBadge.swift
    Digest/            WeeklyDigestView.swift, DigestBuilder.swift
  Sharing/             ShareSheet.swift (UIActivityViewController bridge), PDFExporter.swift, DigestRenderer.swift
  Common/              Config.swift, HTTPClient.swift, AppError.swift
```

Sem SPM/CocoaPods. Tudo via `URLSession` + `Codable`. Princípio: cada arquivo com uma responsabilidade, testável isoladamente.

---

## 5. Modelo de dados (SwiftData)

Todos os modelos nascem **sync-ready** (UUID estável, timestamps, `remoteID` nullable) para a Fase 2 sincronizar sem reescrever. iOS 17.4 como mínimo (predicados SQL estáveis).

### 5.1 Entidades

**Topic** (1→N Post)
- `id: UUID` (`@Attribute(.unique)`)
- `title: String`
- `colorHex: String?`
- `createdAt: Date`, `updatedAt: Date`
- `remoteID: String?`, `syncStatus: SyncStatus = .pending`
- `@Relationship(deleteRule: .cascade, inverse: \Post.topic) posts: [Post]`

**Post** (N↔N Source; N→1 Topic)
- `id: UUID` (`.unique`)
- `title: String`
- `body: String`
- `status: PostStatus` (`.draft` / `.published`)
- `createdAt: Date`, `updatedAt: Date`, `publishedAt: Date?`
- `topic: Topic?`
- `remoteID: String?`, `syncStatus: SyncStatus = .pending`
- `@Relationship(deleteRule: .nullify, inverse: \Source.posts) sources: [Source]`

**Source** (N↔N Post) — o coração
- `id: UUID` (`.unique`)
- `rawInput: String` (o que o usuário colou)
- `kind: SourceKind` (`.doi` / `.pmid` / `.url`)
- `normalizedDOI: String?`
- `pmid: String?`
- `resolvedURL: String?` (landing page)
- `title: String?`, `authors: [String]` (nomes display), `journal: String?`, `year: Int?`, `month: String?`, `day: Int?`, `volume: String?`, `issue: String?`, `pages: String?`, `abstract: String?`, `workType: String?`
- `trustTier: TrustTier` (`.verified` / `.recognized` / `.unverified`)
- `verificationState: VerificationState` (`.pending` / `.completed` / `.failed`)
- `retractionStatus: RetractionStatus` (`.none` / `.retracted` / `.correction` / `.concern`)
- `retractionDate: Date?`, `retractionNoticeDOI: String?`
- `isOpenAccess: Bool`, `oaStatus: String?`, `oaURL: String?`
- `formattedCitation: String?` (Vancouver, derivado)
- `savedStandalone: Bool` (true = "artigo salvo" sem post)
- `topic: Topic?` (tópico onde foi salvo/criado; ajuda a agrupar artigos salvos)
- `createdAt: Date`, `updatedAt: Date`, `fetchedAt: Date?`
- `remoteID: String?`, `syncStatus: SyncStatus = .pending`
- `posts: [Post]` (lado inverso do N↔N; sem `@Relationship` aqui)

> Notas SwiftData: `@Relationship` em **um** lado do N↔N (em `Post.sources`, com `inverse: \Source.posts`). Nunca declarar nos dois lados. Inicializar arrays vazios no `init` e popular **após** `insert` (evita crash "container not loaded"). Deletar Post não apaga Source (`.nullify`); deletar Topic apaga Posts (`.cascade`) mas **não** apaga Sources salvos como artigo.

### 5.2 Enums (string raw value, portáveis p/ backend)

- `SyncStatus`: `pending`, `synced`, `conflict`
- `PostStatus`: `draft`, `published`
- `SourceKind`: `doi`, `pmid`, `url`
- `TrustTier`: `verified`, `recognized`, `unverified`
- `VerificationState`: `pending`, `completed`, `failed`
- `RetractionStatus`: `none`, `retracted`, `correction`, `concern`

### 5.3 Versionamento de schema

`SchemaV1: VersionedSchema` com `versionIdentifier = .init(1,0,0)` e `AppMigrationPlan: SchemaMigrationPlan` com `stages: []` desde o dia 1 — para evoluir com migração leve sem retrabalho.

---

## 6. Motor de verificação (núcleo técnico, sem IA)

### 6.1 Pipeline (ordem de tentativas)

```
Input bruto (string)
│
├─ IdentifierParser detecta o tipo:
│   ├─ DOI (regex)                         → fluxo DOI
│   ├─ PMID (regex / URL pubmed)           → PubMed: PMC ID Converter → DOI (se houver) → fluxo DOI;
│   │                                         sem DOI → efetch (metadados+abstract) → Verificada
│   └─ URL                                 →
│         ├─ contém DOI no path/redirect   → extrai DOI → fluxo DOI
│         ├─ é URL PubMed                   → extrai PMID → fluxo PMID
│         ├─ encurtada                      → HEAD + follow redirect → reprocessa URL final
│         ├─ HTML tem citation_doi/JSON-LD  → extrai DOI → fluxo DOI
│         ├─ domínio na allowlist           → Reconhecida (sem metadados ricos)
│         └─ nada disso                     → Não verificada
│
fluxo DOI:
  1. Crossref /works/{doi}  (PRIMÁRIO)  → título, autores, journal, ano, vol/issue/páginas, abstract?, tipo
  2. Detecção de retratação via `updated-by` (mesmo objeto Crossref)
  3. Unpaywall /v2/{doi}?email=          → is_oa, oa_status, best_oa_location
  4. (opcional, se Config.openAlexKey)   → OpenAlex: reconstruir abstract se faltar + cross-check is_retracted
  5. VancouverFormatter monta a citação
  ⇒ trustTier = .verified
```

### 6.2 Por que Crossref é primário (decisão de arquitetura)

| Critério | Crossref | OpenAlex | doi.org (CSL-JSON) |
|---|---|---|---|
| Precisa de API key? | **Não** (só `User-Agent` com `mailto`) | **Sim** (desde fev/2026; sem key = 100 req/dia) | Não |
| Detecção de retratação | **Sim** (`updated-by`, fonte Retraction Watch) | `is_retracted` (bool) | Não |
| Metadados ricos | Sim | Sim (+ abstract via inverted index) | Básico |
| Open access | Não (usar Unpaywall) | Sim | Não |

Como o **diferencial anti-fake-news é a retratação** e o Crossref entrega isso **sem segredo embutido no app**, ele é o primário. OpenAlex vira enriquecimento **opcional** atrás de `Config.openAlexKey` (preenche abstract quando o Crossref não tem, e dá um segundo voto sobre retratação). Isso mantém o MVP sem chaves e sem risco de vazar credencial num app cliente.

### 6.3 Camadas de confiança (TrustClassifier)

- **Verificada (`.verified`)**: identificador (DOI/PMID) confirmado e metadados resolvidos via Crossref/PubMed.
- **Reconhecida (`.recognized`)**: sem DOI resolvível, mas o domínio (eTLD+1) está na allowlist de fontes confiáveis (sociedades médicas, `.gov`/`.gov.br`, `.edu`, NIH/CDC/OMS/Anvisa, preprint servers, periódicos de alto impacto).
- **Não verificada (`.unverified`)**: nem identificador, nem domínio reconhecido. Publicação permitida, mas o post exibe **aviso visível**.

A allowlist inicial está no Anexo C. Matching: `host == dominio || host.hasSuffix("." + dominio)`.

### 6.4 Retração — sinal ortogonal à camada

`retractionStatus` é independente da camada (um artigo *Verificado* pode estar *Retratado*). Detecção via Crossref:

- `message.updated-by[]` presente → iterar itens:
  - `type == "retraction"` → `.retracted`
  - `type == "expression_of_concern"` → `.concern`
  - `type == "correction"` → `.correction`
- Deduplicar (o mesmo aviso aparece como `source: "publisher"` e `source: "retraction-watch"`).
- Sinal auxiliar: `message.title[0]` com prefixo `"RETRACTED:"`.
- `retractionDate` = `updated.date-parts[0][0]`; `retractionNoticeDOI` = `DOI` do item.

**UI:** fonte retratada exibe banner vermelho ("⚠️ Artigo retratado em {ano}") em **todos** os lugares (preview, página do post, digest), independentemente da camada. O usuário ainda pode salvar (para documentar), mas o selo é inescapável.

### 6.5 Rede, rate limits e robustez

- **Identificação polida (polite pool):** `User-Agent: SciNapse/1.0 (mailto:<Config.contactEmail>)` no Crossref; `?email=<Config.contactEmail>` no Unpaywall (precisa ser e-mail real, senão 422); `tool=SciNapse&email=...` no PubMed/PMC.
- **Rate limits:** Crossref polite ≈ 10 req/s, 3 concorrentes; Unpaywall 100k/dia; PubMed 3 req/s sem key (10 com key). Como é 1 usuário colando manualmente, o volume é trivial — basta tratar 429/5xx com **backoff exponencial + jitter** e no máximo 3 tentativas.
- **Erros distintos por API** (ver Anexo A): Crossref 404 = `text/plain` (checar status antes de decodificar JSON); Unpaywall 404 = HTML; OpenAlex 404 = JSON `{error,message}`, e 301 = DOI merged (seguir redirect).
- **Timeout** por request: 10s. Follow redirect limitado a 10 hops.
- **Offline:** se sem conexão, salva a Source com `verificationState = .pending` e `trustTier = .unverified` (provisório); um botão "Re-verificar" reprocessa quando online. Posts podem ser criados/publicados offline desde que tenham ≥1 fonte (mesmo pendente) — a regra é "ter fonte", não "fonte verificada".

### 6.6 Persistência da verificação (offline-first)

`SourceFetcher` é um `@ModelActor`. Fluxo: **(1)** chamada de rede → **(2)** só após metadados confirmados, `insert(Source)` + `save()` → **(3)** retorna `PersistentIdentifier` (único tipo seguro de cruzar fronteira de actor). Chamar via `Task.detached` para não rodar na main thread. Edição/criação de post usa `ModelContext` isolado com `autosaveEnabled = false` (cancelar = descartar contexto, nada persiste).

---

## 7. Geração de página e citação Vancouver

A "página" do post é uma view SwiftUI composta de:

1. **Cabeçalho** — título, tópico, data, autor (local; na Fase 1 é sempre o dono do device).
2. **Síntese** — o corpo escrito pelo usuário (texto simples; markdown leve é fast-follow).
3. **Fontes** — cards, cada um com: título, autores, journal · ano, **badge de camada**, **alerta de retratação** (se houver), badge **open access** + link (se houver), e a **referência Vancouver** formatada (copiável).

**VancouverFormatter** monta a string a partir dos metadados (regras exatas no Anexo B): autores `Sobrenome Iniciais`, ≤6 listam todos / ≥7 cortam em 6 + `et al.`, journal abreviado sem pontos, `Ano Mês Dia;Vol(Issue):pInício-pFimAbreviado.` + `https://doi.org/{doi}`. Casos de borda cobertos: sem autor, sem volume/issue, preprint, e-location ID.

---

## 8. Digest semanal + exportação

- **DigestBuilder**: dado um Topic e janela (default últimos 7 dias), coleta `Post`s `published` com `publishedAt` na janela, ordena por data, e monta um modelo de digest (título do tópico, período, lista de posts com suas sínteses + fontes resumidas).
- **WeeklyDigestView**: renderiza o digest como página.
- **Exportação/compartilhamento** (Sharing/):
  - **Texto**: versão markdown/plain do digest (título, bullets dos achados, referências) — vai bem em WhatsApp/Mail.
  - **PDF**: `DigestRenderer` rende a view via `ImageRenderer` (com `scale = displayScale`, ambiente injetado) para PDF de página única; conteúdo longo → paginação manual via `UIGraphicsPDFRenderer` (fast-follow se necessário).
  - **Share Sheet**: como precisamos de **texto + arquivo PDF juntos** (heterogêneo), usar `UIActivityViewController` (bridge `ShareSheet`), passando `[markdownString, pdfFileURL]`. Escrever o PDF em arquivo temporário **nomeado** (`digest.pdf`) para AirDrop/Mail preservarem o nome. Configurar `popoverPresentationController` (senão crash no iPad).
- O mesmo mecanismo de export serve a **página de um post individual** (ShareLink simples basta quando é só PDF; usar UIActivityViewController quando combinar texto+PDF).

---

## 9. Telas (responsabilidades)

| Tela | Responsabilidade | Estados-chave |
|---|---|---|
| **TopicListView** | Lista tópicos (`@Query` por `createdAt` desc), criar/renomear/excluir | vazio, lista |
| **TopicDetailView** | Feed do tópico: posts + artigos salvos; ações: Novo post, Salvar artigo, Gerar digest | vazio, conteúdo |
| **AddSourceSheet** | Colar DOI/PMID/URL → dispara verificação → mostra `SourcePreviewView` | digitando, verificando, sucesso, falha, offline/pendente |
| **SourcePreviewView** | Preview dos metadados + badge + alerta retratação + OA; confirmar/descartar | — |
| **ComposePostView** | Título + corpo + anexar fontes; **botão Publicar desabilitado se `sources.isEmpty`**; salvar rascunho | rascunho, pronto-p/-publicar |
| **PostDetailView** | A "página" (seção 7); botão compartilhar | — |
| **WeeklyDigestView** | Página de digest; botão compartilhar | vazio (sem posts na janela), conteúdo |
| **SourceBadge** | Componente: cor/ícone por `TrustTier` + overlay de retratação | verified/recognized/unverified × retracted? |

---

## 10. Tratamento de erros e estados

- **Identificador irreconhecível**: mensagem "Não consegui identificar um artigo nesse texto/link" + opção de salvar mesmo assim como *Não verificada*.
- **DOI inexistente (404)**: "Esse DOI não foi encontrado nas bases" + salvar como Não verificada.
- **Sem conexão**: salva *pendente*, mostra ícone de pendência, botão "Re-verificar".
- **Rate limit (429)**: backoff transparente; se persistir, "Tente novamente em instantes".
- **Publicar sem fonte**: bloqueado com explicação clara da regra (não é bug, é o contrato do produto).
- **Artigo retratado**: nunca bloqueia, mas marca de forma inescapável.

---

## 11. Decisões técnicas e trade-offs

1. **Crossref primário, OpenAlex opcional** — evita embutir API key num app cliente (vazaria) e ainda assim entrega retratação. (§6.2)
2. **Sem dependências externas** — `URLSession`+`Codable` cobrem tudo; menos superfície, builds simples, alinhado a simplicidade. Trade-off: escrever os clients à mão (pouco código, bem testável).
3. **iOS 17.4 mínimo** — predicados SQL do SwiftData estáveis; evita regressões conhecidas de 18.0–18.2. Trade-off: exclui iOS 16/17.0–17.3 (aceitável; base é o device do idealizador).
4. **Camada vs retração ortogonais** — modela a realidade (artigo bom pode ser retratado depois) e evita esconder o sinal mais importante.
5. **Regra "ter fonte" e não "fonte verificada" para publicar** — permite preprints/guidelines legítimos e uso offline, sem abrir mão do selo. Anti-fake-news vem do selo visível, não do bloqueio total.
6. **Export por UIActivityViewController** — única forma de mandar texto + PDF juntos; ShareLink fica para casos homogêneos.

---

## 12. Critérios de aceitação (contrato E2E da Fase 1)

- **AC1 — Persistência:** criar tópico/post/artigo; após relaunch, tudo continua lá.
- **AC2 — DOI verificado:** colar um DOI válido resolve título/autores/journal/ano e mostra badge **Verificada**; salvar no tópico funciona.
- **AC3 — Retração:** colar um DOI de artigo retratado mostra **alerta vermelho de retratação** (fixture de teste: `10.1177/1758835920922055`, retratado em 2023 — confirmado via Crossref `updated-by`).
- **AC4 — Reconhecida:** colar URL de domínio da allowlist sem DOI (ex.: página da OMS) → badge **Reconhecida**.
- **AC5 — Não verificada:** colar link de blog aleatório → badge **Não verificada** + aviso.
- **AC6 — Gate de publicação:** publicar post sem fonte é bloqueado; com ≥1 fonte, publica.
- **AC7 — Página:** abrir o post mostra síntese + fontes com badges + referência Vancouver copiável.
- **AC8 — Digest + share:** gerar digest semanal de um tópico produz a página agregada; compartilhar abre Share Sheet com texto + PDF (PDF abre corretamente).
- **AC9 — Offline:** em modo avião, criar tópico/post/rascunho funciona; ao adicionar fonte, ela fica **pendente**; ao voltar online, "Re-verificar" completa a classificação.
- **AC10 — PMID:** colar um PMID resolve via PubMed (PMC ID Converter → DOI quando existir; senão efetch) e classifica como **Verificada**.

Cada AC vira um teste E2E (XCUITest) ou, no mínimo, um roteiro manual reproduzível antes de considerar a fase concluída.

---

## 13. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| OpenAlex exigir key quebrou o plano original | Médio | Já tratado: Crossref primário, OpenAlex opcional |
| `Config.contactEmail` placeholder → Unpaywall 422 | Baixo | Documentar que precisa ser e-mail real do dono; default configurável |
| Variedade de páginas sem `citation_doi` | Médio | Cascata: meta tags → JSON-LD → allowlist → Não verificada (degrada com graça) |
| PDF rasterizado grande/borrado | Baixo | `scale = displayScale`; migrar p/ `UIGraphicsPDFRenderer` se precisar de texto vetorial/paginação |
| Bulk insert lento no SwiftData | Baixo (volume 1 usuário) | Inserções em background actor; não é gargalo na Fase 1 |
| Retração só detectada por uma fonte | Baixo | Crossref já integra Retraction Watch; OpenAlex `is_retracted` como 2º voto opcional |

---

## 14. Ponte para a Fase 2 (compartilhamento)

Backend pequeno (Railway: API enxuta + Postgres) para tópicos públicos, colegas e sincronização. O modelo de dados já está pronto: `id` UUID estável (upsert), `createdAt/updatedAt` (delta sync e resolução de conflito), `remoteID` e `syncStatus` por entidade. Nada na Fase 1 trava a migração. Auth, feed e moderação ficam para o spec da Fase 2.

---

## Anexo A — Contratos de API (resumo)

**Crossref** `GET https://api.crossref.org/v1/works/{doi}` · `User-Agent: SciNapse/1.0 (mailto:…)` · resposta em `message.*`: `DOI`, `title[0]`, `author[].{given,family,sequence}`, `container-title[0]`, `issued.date-parts[0][0]` (fallback `published-print`/`published-online`), `volume`, `issue`, `page`, `abstract` (JATS, opcional), `type`, `updated-by[]` (retração). 404 = `text/plain`. Polite ≈10 req/s.

**Unpaywall** `GET https://api.unpaywall.org/v2/{doi}?email=…` · `is_oa`, `oa_status` (gold/green/hybrid/bronze/closed), `best_oa_location.{url,url_for_pdf,url_for_landing_page,host_type,license,version}`. 404 = HTML; 422 = email inválido. 100k/dia.

**PubMed E-utilities** · ESummary `GET …/esummary.fcgi?db=pubmed&id={pmid}&retmode=json` → `result.{pmid}.{title,fulljournalname,source,pubdate,authors[].name,articleids[]}` (DOI em `articleids` onde `idtype=="doi"`). EFetch `…/efetch.fcgi?db=pubmed&id={pmid}&retmode=xml` → abstract em `//Abstract/AbstractText`. 3 req/s sem key. `tool`+`email` recomendados.

**PMC ID Converter** `GET https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/?ids={id}&format=json&tool=SciNapse&email=…` → `records[0].{pmid,pmcid,doi}`. Até 200 ids.

**OpenAlex (opcional)** `GET https://api.openalex.org/works/doi:{doi}?api_key=…` → `title`, `publication_year`, `authorships[].author.display_name`, `primary_location.source.display_name`, `is_retracted`, `open_access.*`, `abstract_inverted_index` (reconstruir). Sem key: 100 req/dia (409). 404=JSON, 301=merged.

## Anexo B — Regras Vancouver (resumo)

`{Autores}. {Título}. {JournalAbbrev}. {Ano}[ {Mês}][ {Dia}];{Vol}({Issue}):{pIni}-{pFimAbrev}. https://doi.org/{doi}`
- Autores: `Sobrenome Iniciais` (sem pontos), separados por `, `; ≤6 todos; ≥7 → 6 + `, et al.`
- Páginas abreviadas: `284-287`→`284-7`, `1432-1440`→`1432-40`.
- Sem autor → começa pelo título. Sem volume → `Ano:páginas`. Preprint → `Server [Preprint]. Ano [posted …; cited …]. DOI`. E-location ID (ex.: `e202301234`) no lugar das páginas.

## Anexo C — Domain allowlist inicial (eTLD+1)

Órgãos: `nih.gov`, `ncbi.nlm.nih.gov`, `cdc.gov`, `fda.gov`, `who.int`, `paho.org`, `ema.europa.eu`, `ecdc.europa.eu`, `anvisa.gov.br`, `saude.gov.br`, `fiocruz.br`, `scielo.br`, `clinicaltrials.gov`, `cochranelibrary.com`, `europepmc.org`.
Preprints: `medrxiv.org`, `biorxiv.org`, `arxiv.org`, `researchsquare.com`, `ssrn.com`, `osf.io`, `zenodo.org`, `figshare.com`.
Periódicos/editoras: `nejm.org`, `thelancet.com`, `bmj.com`, `jamanetwork.com`, `nature.com`, `science.org`, `cell.com`, `pnas.org`, `springer.com`, `link.springer.com`, `wiley.com`, `onlinelibrary.wiley.com`, `sciencedirect.com`, `academic.oup.com`, `karger.com`, `tandfonline.com`, `mdpi.com`, `frontiersin.org`, `plos.org`, `elifesciences.org`.
Sociedades: `ahajournals.org`, `diabetesjournals.org`, `atsjournals.org`, `acpjournals.org`, `annals.org`, `ascopubs.org`, `endocrine.org`, `jci.org`.
> Lista curável; deve virar um arquivo de recurso versionável.

## Anexo D — Regex de identificadores

- DOI: `^10\.\d{4,9}/[-._;()/:A-Z0-9]+$` (case-insensitive). Em texto livre: `\b(10\.\d{4,9}/[-._;()/:A-Z0-9]+)\b` (remover pontuação final do match).
- PMID isolado: `^[1-9]\d{0,7}$`. Em texto: `(?:PMID[:\s]+)([1-9]\d{0,7})\b`. URL PubMed: `pubmed\.ncbi\.nlm\.nih\.gov/([1-9]\d{0,7})`.
- Regra de desempate: contém `/` e começa com `10.` → DOI; só dígitos → PMID.
