import { pathToFileURL } from "node:url";

const endpoint = "https://wrpwitehcikplsauiwmg.supabase.co/rest/v1/app_settings?select=id&limit=1";
const publishableKey = "sb_publishable_-HmWs8oJ651q7_Qqrd-rWA_KXwOYDgd";

// A real, read-only application query. Never use a service-role key for this check.
export async function checkDatabase(fetcher = fetch) {
  const response = await fetcher(endpoint, {
    method: "GET",
    headers: { apikey: publishableKey, Accept: "application/json", "Cache-Control": "no-cache" },
    cache: "no-store",
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error("Database non raggiungibile: HTTP " + response.status);
  let rows;
  try { rows = await response.json(); }
  catch { throw new Error("Risposta database non valida"); }
  if (!Array.isArray(rows) || rows.length !== 1 || rows[0].id !== true) {
    throw new Error("Configurazione pubblica BarberCut non disponibile");
  }
  return true;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await checkDatabase();
    console.log(new Date().toISOString() + " — Database BarberCut raggiungibile.");
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Controllo database non riuscito");
    process.exitCode = 1;
  }
}
