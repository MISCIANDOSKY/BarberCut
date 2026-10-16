import { createClient } from "npm:@supabase/supabase-js@2.57.4";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  let notice = ""; let token = ""; let claimed = false; let sent = false;
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    const body = await req.text();
    if (body.length > 1024) return new Response("Invalid request", { status: 400 });
    const input = JSON.parse(body);
    notice = input.notice_id; token = input.token;
    if (typeof notice !== "string" || typeof token !== "string" || !/^[0-9a-f-]{36}$/.test(notice) || !/^[0-9a-f-]{72}$/.test(token)) {
      return new Response("Access denied", { status: 401 });
    }
    // A short-lived, single-use queue token authenticates this scheduled request.
    // The caller cannot supply an email address, warning text or recipient.
    const { data, error } = await admin.rpc("claim_inactivity_notice", { p_notice: notice, p_token: token });
    if (error) return new Response("Unavailable", { status: 503 });
    if (!data) return new Response("Access denied", { status: 401 });
    if (data.cancelled) return Response.json({ cancelled: true });
    claimed = true;
    const mailer = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
    // Reuse the existing Auth SMTP delivery and its conditional Italian template.
    // Requesting an email does not sign in the user or reset their inactivity.
    const { error: mailError } = await mailer.auth.signInWithOtp({
      email: data.email,
      options: { shouldCreateUser: false, emailRedirectTo: "https://misciandosky.github.io/BarberCut/?keep-active=1" },
    });
    if (mailError) return new Response("Email delivery failed", { status: 503 });
    sent = true;
    return Response.json({ accepted: true });
  } catch {
    return new Response("Unavailable", { status: 503 });
  } finally {
    if (claimed) {
      await admin.rpc("finish_inactivity_notice", { p_notice: notice, p_token: token, p_sent: sent });
    }
  }
});
