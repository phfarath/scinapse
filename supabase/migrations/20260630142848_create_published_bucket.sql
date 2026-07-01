-- SciNapse Fase 2a — bucket público que serve o HTML das páginas vivas.
-- Edge Functions não servem text/html (são reescritas p/ text/plain); o Storage CDN serve.
-- public = true → leitura por URL sem auth. Sem policy de list → objetos não enumeráveis
-- (slug aleatório). Escrita só via service_role (na função publish).

insert into storage.buckets (id, name, public)
values ('published', 'published', true)
on conflict (id) do nothing;
