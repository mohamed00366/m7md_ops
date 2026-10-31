// valet-photo-cleanup (DB 330): removes car / damage photos older than "photo keep days" (dashboard) via the Storage API.
// Deployed with the Management API (verify_jwt = false); called every night by cron 'valet-photo-cleanup' with x-vv-secret.
import { createClient } from 'npm:@supabase/supabase-js@2';
Deno.serve(async (req) => {
  const secret = req.headers.get('x-vv-secret') ?? '';
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  let removed = 0;
  for (let round = 0; round < 20; round++) {
    const { data, error } = await sb.rpc('vv_photo_cleanup_list', { p_secret: secret, p_limit: 500 });
    if (error) return new Response(JSON.stringify({ ok: false, error: error.message }), { status: 500 });
    if (!data?.ok) return new Response(JSON.stringify(data), { status: 403 });
    const paths: string[] = data.paths ?? [];
    if (!paths.length) break;
    for (let i = 0; i < paths.length; i += 100) {
      const { error: e2 } = await sb.storage.from('valet-car-photos').remove(paths.slice(i, i + 100));
      if (e2) return new Response(JSON.stringify({ ok: false, error: e2.message, removed }), { status: 500 });
      removed += Math.min(100, paths.length - i);
    }
  }
  return new Response(JSON.stringify({ ok: true, removed }), { headers: { 'Content-Type': 'application/json' } });
});
