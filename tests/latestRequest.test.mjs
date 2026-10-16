import test from "node:test";
import assert from "node:assert/strict";
import { createLatestRequest } from "../src/lib/latestRequest.mjs";
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
test("Una risposta vecchia non sovrascrive gli slot aggiornati", async () => {
  const first = deferred(), second = deferred(), published = [];
  let call = 0;
  const request = createLatestRequest({ load: () => (++call === 1 ? first.promise : second.promise), onData: (d) => published.push(d), onError: assert.fail });
  const old = request.refresh(), fresh = request.refresh();
  second.resolve(["10:00"]); await fresh;
  first.resolve(["09:00"]); await old;
  assert.deepEqual(published, [["10:00"]]);
});
test("Una sezione chiusa ignora dati ed errori arrivati dopo", async () => {
  for (const fails of [false, true]) {
    const pending = deferred(), published = [];
    const request = createLatestRequest({ load: () => pending.promise, onData: (d) => published.push(d), onError: (e) => published.push(e) });
    const running = request.refresh(); request.stop();
    if (fails) pending.reject(new Error("offline")); else pending.resolve(["09:00"]);
    await running; assert.deepEqual(published, []);
  }
});
test("Un errore della richiesta corrente viene gestito", async () => {
  const error = new Error("offline"), received = [];
  const request = createLatestRequest({ load: async () => { throw error; }, onData: assert.fail, onError: (e) => received.push(e) });
  await request.refresh(); assert.deepEqual(received, [error]);
});
