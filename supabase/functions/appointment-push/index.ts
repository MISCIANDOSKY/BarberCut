import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import webpush from "npm:web-push@3.6.7";

const database = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
const allowedEndpoint = (endpoint: string) => {
  try {
    const u = new URL(endpoint);
    return u.protocol === "https:" && !u.username && !u.password && !u.port &&
      (u.hostname === "fcm.googleapis.com" || u.hostname === "web.push.apple.com" ||
      /(^|\.)push\.services\.mozilla\.com$/.test(u.hostname) || /(^|\.)notify\.windows\.com$/.test(u.hostname));
  } catch { return false; }
};
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (Number(request.headers.get("content-length") || 0) > 2048) return new Response("Invalid request", { status: 400 });
  let input: { action?: string; token?: string; delivery_id?: string; kind?: string };
  try { const raw = await request.text(); if (raw.length > 2048) return new Response("Invalid request", {status: 400}); input = JSON.parse(raw); }
  catch { return new Response("Invalid request", {status: 400}); }
  if (!input || typeof input.token !== "string" || input.token.length < 32 || input.token.length > 200) return new Response("Unauthorized", {status: 401});
  try {
    if (input.action === "setup") {
      const { data: allowed, error } = await database.rpc("push_setup_allowed", {p_token: input.token});
      if (error || allowed !== true) return new Response("Unauthorized", {status: 401});
      const keys = webpush.generateVAPIDKeys();
      const saved = await database.rpc("complete_push_setup", {p_token: input.token, p_public: keys.publicKey, p_private: keys.privateKey});
      if (saved.error) return new Response("Setup failed", {status: 500});
      return Response.json({ready: true});
    }
    if (input.action !== "send" || typeof input.delivery_id !== "string" || !/^[0-9a-f-]{36}$/.test(input.delivery_id)) return new Response("Invalid request", {status: 400});
    const { data: job, error } = await database.rpc(input.kind === "message" ? "claim_message_push" : "claim_appointment_push", {p_delivery: input.delivery_id, p_token: input.token});
    if (error) return new Response("Unavailable", {status: 503});
    if (!job) return new Response(null, {status: 204});
    let outcome = "failed";
    if (!allowedEndpoint(job.subscription.endpoint)) outcome = "expired";
    else {
      try {
        await webpush.sendNotification(job.subscription, JSON.stringify(job.payload), {
          vapidDetails: {subject: "https://misciandosky.github.io/BarberUp/", publicKey: job.public_key, privateKey: job.private_key},
          TTL: job.ttl, urgency: "normal", timeout: 12000,
        });
        outcome = "sent";
      } catch (error) {
        const status = Number((error as { statusCode?: number }).statusCode);
        if (status === 404 || status === 410) outcome = "expired";
      }
    }
    const done = await database.rpc(input.kind === "message" ? "finish_message_push" : "finish_appointment_push", {p_delivery: input.delivery_id, p_token: input.token, p_outcome: outcome});
    return Response.json({processed: !done.error}, {status: done.error ? 503 : 200});
  } catch {
    return new Response("Unavailable", {status: 503});
  }
});
