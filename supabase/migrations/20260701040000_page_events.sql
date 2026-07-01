-- SciNapse Fase 2a (Onda 1) — eventos de página: reações e cliques em fontes.
-- Tabela genérica de eventos por slug; escrita só via RPC (SECURITY DEFINER),
-- sem grant de select/insert direto pra anon/authenticated.

create table if not exists public.page_events (
    id          uuid primary key default gen_random_uuid(),
    slug        text not null,
    kind        text not null,             -- 'reaction' | 'source_click'
    value       text,                       -- ex: 'useful'/'not_useful' (reaction) ou tier (source_click)
    ref         text,                       -- ex: url/id da fonte clicada
    created_at  timestamptz not null default now()
);

comment on table public.page_events is
    'Eventos de página (reações, cliques em fontes) do SciNapse. Escrita só via RPC (SECURITY DEFINER).';

create index if not exists page_events_slug_idx on public.page_events (slug);

-- RLS: habilitado, sem policies de select/insert pra anon/authenticated.
-- Toda leitura/escrita acontece via RPC SECURITY DEFINER (bypassa RLS) ou service_role.
alter table public.page_events enable row level security;

-- RPC: registra reação (útil / não útil) pra uma página.
create or replace function public.record_reaction(p_slug text, p_value text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_value not in ('useful', 'not_useful') then
        return;
    end if;

    insert into public.page_events (slug, kind, value)
    values (p_slug, 'reaction', p_value);
end;
$$;

-- RPC: registra clique numa fonte (tier + referência da fonte).
create or replace function public.record_source_click(p_slug text, p_tier text, p_ref text)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.page_events (slug, kind, value, ref)
    values (p_slug, 'source_click', p_tier, p_ref);
$$;

-- RPC: estatísticas agregadas de uma página (views + reações + cliques em fontes).
create or replace function public.page_stats(p_slug text)
returns json
language sql
security definer
set search_path = public
stable
as $$
    select json_build_object(
        'views', coalesce((select views from public.published_topics where slug = p_slug), 0),
        'useful', (select count(*) from public.page_events where slug = p_slug and kind = 'reaction' and value = 'useful'),
        'not_useful', (select count(*) from public.page_events where slug = p_slug and kind = 'reaction' and value = 'not_useful'),
        'source_clicks', (select count(*) from public.page_events where slug = p_slug and kind = 'source_click')
    );
$$;

-- Privilégios: sem grant de select/insert na tabela pra anon/authenticated;
-- só execução das RPCs, que rodam como owner (SECURITY DEFINER).
revoke all on function public.record_reaction(text, text) from public;
grant execute on function public.record_reaction(text, text) to anon, authenticated;

revoke all on function public.record_source_click(text, text, text) from public;
grant execute on function public.record_source_click(text, text, text) to anon, authenticated;

revoke all on function public.page_stats(text) from public;
grant execute on function public.page_stats(text) to anon, authenticated;
