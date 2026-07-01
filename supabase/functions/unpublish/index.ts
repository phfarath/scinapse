// SciNapse Fase 2a — edge function `unpublish`.
// Remove a página publicada de um slug (tira do ar). Gated pelo PUBLISH_SECRET.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const expected = Deno.env.get("PUBLISH_SECRET");
  if (!expected || body?.secret !== expected) return json({ error: "unauthorized" }, 401);

  const slug = typeof body?.slug === "string" ? body.slug : "";
  if (!slug) return json({ error: "missing_slug" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { error } = await supabase.from("published_topics").delete().eq("slug", slug);
  if (error) return json({ error: "db_error", detail: error.message }, 500);

  return json({ ok: true }, 200);
});
