# SciNapse — Fase 2a: Publicar tópico como link web (página viva)

- **Data:** 2026-06-30
- **Status:** Aprovado (brainstorming) — pronto para virar plano de implementação
- **Antecede:** [Fase 1 — design](2026-06-28-scinapse-fase1-design.md)
- **Sucede para:** Fase 2b (contas + seguir + notificações push)

## Contexto e objetivo

A Fase 1 entregou o app *autor* (device-only, single user): tópicos, sínteses autorais com fontes verificadas, digest semanal, share extension e export PDF. Nada do conteúdo sai do iPhone.

A visão do pai do usuário é **broadcast**: ele salva as publicações da semana e **compartilha com residentes/colegas**. Decidimos seguir a abordagem **C (híbrida), começando pelo caminho mais barato (A)**: distribuir o conteúdo como **link web público read-only**, antes de construir contas/feed/notificações (2b). O objetivo único da 2a é responder com baixo custo: **os residentes leem?**

Esta fase entrega: um botão **"Publicar / Atualizar página"** no app que transforma um tópico numa **página web viva** (uma URL estável por tópico que sempre reflete o conteúdo atual), compartilhável via WhatsApp/link.

## Não-objetivos (ficam para 2b ou depois)

- Contas/login de leitor, seguir tópicos, feed personalizado, notificações push.
- Comunidade (terceiros publicando) — segue sendo publicador único (o pai).
- Domínio customizado (usamos o domínio padrão `*.supabase.co` por ora).
- Snapshots semanais arquivados — escolhemos **página viva** (um link por tópico, sempre atual). O recorte "Esta semana" pode ser uma seção dentro da página, não um link separado.
- Comentários/reações na página pública.

## Decisões

1. **Unidade de publicação:** **página viva por tópico.** Um `slug` estável por tópico; "Publicar" cria na 1ª vez e **atualiza a mesma URL** nas próximas. O app guarda o `slug` retornado por tópico.
2. **Backend:** **Supabase** (Postgres + Edge Functions + Storage; on-ramp natural para auth/realtime/push no 2b).
3. **Ops/escopo:** Supabase CLI **escopado à pasta do repo** (`supabase/` versionado), **remote-only** (sem stack local em Docker → zero conflito de porta com outros projetos do usuário). Comandos sempre rodados do repo, linkado só ao `project-ref` do SciNapse.
4. **Renderização:** a página pública é uma **página leitora estática** (`reader/index.html`) hospedada no **GitHub Pages** (`phfarath/scinapse` → `https://phfarath.github.io/scinapse/`), que busca a linha do Supabase via **REST** (pelo `slug` no fragmento `#`) e **renderiza no cliente**. Reaproveita os dados estruturados para o app leitor do 2b.
   - **Por quê não a edge function servir o HTML:** o Supabase **reescreve `text/html` → `text/plain`** (anti-phishing) em Edge Functions **e** Storage no domínio padrão `*.supabase.co` — confirmado empiricamente e na doc. Servir HTML de verdade exigiria custom domain (pago). O split "Supabase = API de dados + front estático em host grátis" é o próprio caminho recomendado pela doc do Supabase, e mantém tudo grátis.
5. **Auth de publicação:** um **`PUBLISH_SECRET`** compartilhado (env var na função + embutido no app). Publicador único por ora; troca por Supabase Auth real no 2b.
6. **Visibilidade:** **link compartilhável + `noindex`** (não cai em buscadores), `slug` aleatório não-enumerável (token de 8–10 chars). "Público com o link", não "público no Google".
7. **Portão anti-fake-news preservado:** o gate "sem fonte não publica" continua no app; a página pública exibe os mesmos **badges de tier** e **flags de retratação** com links verificáveis.

## Arquitetura

```
[iOS app / SwiftData]  --publish(snapshot, secret)-->  [Edge Function: publish]
                                                              |
                                                        upsert (service_role)
                                                              v
                                                     [Postgres: published_topics]
                                                              ^
                                                     REST select (RLS public read)
                                                              |
[Navegador do residente] --GET Pages /#<slug>--> [reader/index.html @ GitHub Pages] --fetch+render no cliente-->
```

- O **app continua dono dos dados** (SwiftData no device). Publicar envia um *snapshot* serializado; o Supabase guarda a versão pública mais recente.
- **Escrita** no banco só acontece dentro da função `publish` (com service_role injetada). O público nunca escreve.
- **Leitura** é pública (é o objetivo do link).

## Modelo de dados (Postgres)

Tabela `public.published_topics`:

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `uuid` PK default `gen_random_uuid()` | |
| `slug` | `text` unique not null | token aleatório (8–10 chars, base62), gerado na 1ª publicação |
| `title` | `text` not null | título do tópico |
| `data` | `jsonb` not null | snapshot estruturado (ver abaixo) |
| `created_at` | `timestamptz` default `now()` | |
| `updated_at` | `timestamptz` default `now()` | atualizado a cada publish |

**RLS:** habilitado.
- Policy **SELECT**: `using (true)` para o role `anon` (leitura pública).
- **Sem** policy de INSERT/UPDATE/DELETE para `anon`/`authenticated` → escrita só via service_role (na função `publish`, que bypassa RLS).

**Índice:** unique em `slug` (já pela constraint).

### Formato do snapshot (`data` jsonb)

```jsonc
{
  "title": "string",
  "publishedAt": "ISO-8601",
  "syntheses": [
    {
      "id": "uuid",
      "text": "síntese autoral (markdown leve ou texto)",
      "date": "ISO-8601",
      "sources": [
        {
          "title": "string",
          "authors": ["string"],
          "container": "journal/venue",
          "year": 2025,
          "identifier": { "kind": "doi|pmid|url", "value": "string" },
          "url": "https://…",
          "vancouver": "citação formatada",
          "tier": "verified|recognized|unverified",
          "retraction": "none|retracted|correction|concern"
        }
      ]
    }
  ]
}
```

O app monta esse JSON a partir do `Topic` (posts/sínteses + suas `Source`s, reusando o `VancouverFormatter` e os campos já existentes no `SciNapseKit`).

## Backend: 1 Edge Function + 1 página leitora

### `publish` (POST) — `supabase/functions/publish/index.ts`
- **Entrada:** `{ slug?: string, title: string, data: <snapshot>, secret: string }`.
- **Auth da chamada:** header `Authorization: Bearer <anon key>` (exigência padrão do gateway de functions) **+** validação do `secret` contra `PUBLISH_SECRET` (env). Sem o secret correto → 401.
- **Lógica:** `upsert` por `slug` (gera token aleatório de 10 chars se ausente), escrevendo com `SUPABASE_SERVICE_ROLE_KEY` (auto-injetada, bypassa RLS).
- **Saída:** `{ slug, url }` onde `url = ${READER_BASE_URL}#${slug}` (env `READER_BASE_URL = https://phfarath.github.io/scinapse/`).

### `reader/index.html` (página leitora estática) — GitHub Pages `phfarath/scinapse`
- Arquivo único (HTML+CSS+JS inline), servido em `https://phfarath.github.io/scinapse/`.
- No load, lê o `slug` de `location.hash`, faz `fetch` em `.../rest/v1/published_topics?slug=eq.<slug>` com a **anon key** (RLS permite leitura pública) e **renderiza no cliente**: título, cada síntese (texto + data) e sob ela as fontes com **citação Vancouver**, **badge de tier**, **flag de retratação** e **link**.
- `<meta name="robots" content="noindex">`, mobile-first, paleta da marca. Estados: carregando / não encontrado / erro.
- Read-only. Sempre reflete o último publish (página viva) porque lê a linha ao vivo.
- O `anon key` e o `SUPABASE_URL` ficam inline no arquivo (públicos por design; RLS protege).

## Mudanças no app iOS

- **Persistência local:** guardar o `slug` publicado por tópico (campo novo `publishedSlug: String?` no `Topic`, ou tabela paralela). Permite re-publicar atualizando a mesma URL e exibir estado "Publicado".
- **Ação "Publicar / Atualizar página"** no tópico (e/ou na tela de digest): monta o snapshot, chama a função `publish` (URL + anon key + secret), trata erro/loading, salva o `slug` retornado.
- **Estado publicado:** mostrar "Publicado ✓ — Copiar link / Compartilhar" (share sheet) e "Atualizar página" quando já houver `slug`.
- **Config:** `Config` no `SciNapseKit` ganha `supabaseURL`, `supabaseAnonKey` e `publishSecret` (constantes de build; o secret não é segredo forte nesta fase, é barreira contra escrita acidental por terceiros).
- **Camada de rede:** um cliente fino (URLSession + Codable) em `SciNapseKit` (`PublishClient`) — testável com fixtures, sem dependências externas.

## Segurança

- **RLS** garante leitura pública mas **nenhuma escrita** pública.
- **service_role** nunca sai do servidor (auto-injetada na função).
- **anon key** é pública por design (protegida por RLS) — ok embutir no app.
- **`PUBLISH_SECRET`** é barreira simples contra escrita acidental/abuso trivial; **não** é mecanismo forte (fica no binário do app). Aceitável para publicador único; substituído por Auth real no 2b.
- **`noindex`** + slug aleatório → conteúdo não some em buscadores nem é enumerável.

## Ops / setup (escopado à pasta)

1. Usuário cria o projeto no dashboard (região `sa-east-1` São Paulo), guarda a senha do banco.
2. `supabase login` (token global da conta — não amarra projeto).
3. No repo: `supabase init` → cria `supabase/` aqui. `supabase link --project-ref <REF>` → linka **só** esta pasta ao projeto SciNapse.
4. Schema via migration (`supabase/migrations/…`) aplicada com `supabase db push`.
5. Funções em `supabase/functions/publish` e `supabase/functions/page`, deploy com `supabase functions deploy`.
6. `supabase secrets set PUBLISH_SECRET=<gerado>`.
7. Remote-only: **não** rodar `supabase start`.

## Critérios de aceitação

1. Publicar um tópico no app retorna uma URL e salva o `slug` localmente.
2. Abrir a URL num navegador anônimo mostra título, sínteses e, sob cada síntese, as fontes com citação Vancouver, badge de tier e link.
3. Fonte retratada aparece com flag de retratação na página pública.
4. Editar o tópico no app e **republicar** atualiza a **mesma URL** (página viva), sem gerar link novo.
5. Tentativa de escrita direta na tabela com a anon key (sem service_role) é **negada** pela RLS.
6. Chamada à função `publish` sem o `PUBLISH_SECRET` correto retorna 401 e não escreve.
7. A página responde `noindex`; o `slug` é aleatório (não sequencial/enumerável).
8. Todo o setup Supabase vive em `supabase/` no repo, linkado a um único `project-ref`, sem stack local — sem conflito com outros projetos do usuário.

## Riscos / questões em aberto

- **Tamanho do snapshot:** tópicos grandes geram jsonb grande; aceitável no MVP (jsonb do Postgres aguenta), normalizamos em tabelas no 2b se precisar.
- **Domínio:** URL `*.supabase.co` é feia para compartilhar; custom domain é trivial de adicionar depois.
- **Auth fraca de publicação:** assumido conscientemente para o MVP; 2b resolve.
- **Migração 2a→2b:** o `data` jsonb já carrega a estrutura que o app leitor vai consumir; a passagem para tabelas normalizadas + Auth é evolutiva, não recomeço.
