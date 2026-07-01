-- SciNapse Fase 2a — contador de visualizações (sem contas).

alter table public.published_topics
    add column if not exists views bigint not null default 0;

-- Incremento chamável por anon SEM conceder UPDATE na tabela.
-- security definer roda como owner (bypassa RLS) e só faz o incremento pontual.
create or replace function public.increment_views(p_slug text)
returns void
language sql
security definer
set search_path = public
as $$
    update public.published_topics set views = views + 1 where slug = p_slug;
$$;

revoke all on function public.increment_views(text) from public;
grant execute on function public.increment_views(text) to anon, authenticated;
