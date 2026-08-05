import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data, error } = await supabase.rpc("_qa_s1x_run2");
  return new Response(JSON.stringify({ data, error }, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
});
