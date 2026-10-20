import test from "node:test";
import assert from "node:assert/strict";
import { romeDay, maxBookingDate, romeLocalToISO } from "../src/lib/dates.mjs";
test("Limite sei mesi con fine mese", () => {
  assert.equal(maxBookingDate(new Date("2026-01-31T12:00:00Z")), "2026-07-31");
  assert.equal(maxBookingDate(new Date("2026-08-31T12:00:00Z")), "2027-02-28");
  assert.equal(maxBookingDate(new Date("2026-10-16T12:00:00Z")), "2027-04-16");
});
test("La data segue Roma anche vicino a mezzanotte", () =>
  assert.equal(romeDay(new Date("2026-10-16T22:30:00Z")), "2026-10-17"));
test("Conversione Europe/Rome inverno ed estate", () => {
  assert.equal(romeLocalToISO("2026-12-01T10:00"), "2026-12-01T09:00:00.000Z");
  assert.equal(romeLocalToISO("2026-07-01T10:00"), "2026-07-01T08:00:00.000Z");
});
test("Ora inesistente durante passaggio estivo rifiutata", () =>
  assert.throws(() => romeLocalToISO("2027-03-28T02:30")));
