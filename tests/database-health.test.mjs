import test from "node:test";
import assert from "node:assert/strict";
import { checkDatabase } from "../scripts/check-database.mjs";

test("Il controllo legge solo l'identificatore pubblico, senza scrivere dati", async () => {
  let request;
  const ok = await checkDatabase(async (url, options) => {
    request = { url, options };
    return { ok: true, json: async () => [{ id: true }] };
  });
  assert.equal(ok, true);
  assert.equal(request.options.method, "GET");
  assert.equal(request.options.cache, "no-store");
  assert.equal(new URL(request.url).searchParams.get("select"), "id");
  assert(request.options.headers.apikey.startsWith("sb_publishable_"));
  assert.equal(request.options.body, undefined);
});
test("Un errore del servizio fa fallire il controllo senza esporre la risposta", async () => {
  await assert.rejects(
    checkDatabase(async () => ({ ok: false, status: 503 })),
    /HTTP 503/,
  );
});
test("Una risposta vuota o inattesa non viene scambiata per database sano", async () => {
  for (const rows of [[], {}, [{ id: false }]]) {
    await assert.rejects(
      checkDatabase(async () => ({ ok: true, json: async () => rows })),
      /non disponibile/,
    );
  }
});
test("JSON corrotto e assenza di rete vengono segnalati", async () => {
  await assert.rejects(
    checkDatabase(async () => ({
      ok: true,
      json: async () => {
        throw new Error("invalid json");
      },
    })),
    /non valida/,
  );
  await assert.rejects(
    checkDatabase(async () => {
      throw new Error("offline");
    }),
    /offline/,
  );
});
