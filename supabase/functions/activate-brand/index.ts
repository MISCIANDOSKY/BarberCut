// Retired: scheduled naming is handled atomically in Postgres. SMTP remains unchanged.
Deno.serve(() => new Response("Retired", { status: 410 }));
