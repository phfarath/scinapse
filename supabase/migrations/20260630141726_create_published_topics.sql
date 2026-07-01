-- SciNapse Fase 2a — página viva por tópico.
-- Snapshot público de um tópico (título + sínteses + fontes), servido como link web.

create table if not exists public.published_topics (
    id          uuid primary key default gen_random_uuid(),
    slug        text not null unique,          -- token aleatório, não-enumerável
    title       text not null,
    data        jsonb not null,                -- snapshot estruturado (sínteses + fontes)
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

comment on table public.published_topics is
    'Snapshot público (página viva) de um tópico do SciNapse. Escrita só via edge function publish (service_role).';

-- RLS: leitura pública, escrita negada ao público.
alter table public.published_topics enable row level security;

-- Leitura pública: qualquer um (anon) pode ler uma página publicada.
-- Também serve o futuro app leitor (Fase 2b), que lê direto com a anon key.
create policy "public read published topics"
    on public.published_topics
    for select
    to anon, authenticated
    using (true);

-- Sem policy de INSERT/UPDATE/DELETE para anon/authenticated → escrita bloqueada.
-- A edge function 'publish' escreve usando service_role, que bypassa RLS.

-- Privilégios: só leitura para os papéis públicos.
grant select on public.published_topics to anon, authenticated;
