// SciNapse Fase 2a — edge function `publish`.
// 1) valida o PUBLISH_SECRET
// 2) faz upsert da linha estruturada em published_topics
// 3) devolve a URL da página leitora (GitHub Pages) com o slug no fragmento (#).
// O HTML é renderizado no cliente pela página leitora, que busca esta linha via REST
// (Edge Functions/Storage do Supabase não servem text/html no domínio padrão).
// Página viva: re-publicar o mesmo slug sobrescreve a linha.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const SLUG_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
function randomSlug(len = 10): string {
  const bytes = new Uint8Array(len);
  crypto.getRandomValues(bytes);
  let s = "";
  for (const b of bytes) s += SLUG_ALPHABET[b % SLUG_ALPHABET.length];
  return s;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const expected = Deno.env.get("PUBLISH_SECRET");
  if (!expected || body?.secret !== expected) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const title = typeof body?.title === "string" ? body.title.trim() : "";
  const data = body?.data;
  if (!title || data === undefined || data === null) {
    return jsonResponse({ error: "missing_title_or_data" }, 400);
  }

  const slug = (typeof body?.slug === "string" && body.slug.length > 0)
    ? body.slug
    : randomSlug();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { error } = await supabase
    .from("published_topics")
    .upsert({ slug, title, data, updated_at: new Date().toISOString() }, { onConflict: "slug" });
  if (error) return jsonResponse({ error: "db_error", detail: error.message }, 500);

  const readerBase = Deno.env.get("READER_BASE_URL") ?? "https://phfarath.github.io/scinapse-reader/";
  return jsonResponse({ slug, url: `${readerBase}#${slug}` }, 200);
});
