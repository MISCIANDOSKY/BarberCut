import test from "node:test";
import assert from "node:assert/strict";
import { createCalendar } from "../src/lib/calendar.mjs";
const first = {
  id: "test-first",
  start_at: "2026-10-24T10:00:00+02:00",
  end_at: "2026-10-24T10:30:00+02:00",
  service_name: "Taglio",
  barber_name: "Collaboratore",
};
test("calendar exports exact instants across daylight saving and stable appointment identifiers", () => {
  const later = {
    ...first,
    id: "test-later",
    start_at: "2026-10-31T10:00:00+01:00",
    end_at: "2026-10-31T10:30:00+01:00",
  };
  const output = createCalendar(
    [first, later, first],
    new Date("2026-10-20T12:00:00Z"),
  );
  assert.equal(output.match(/BEGIN:VEVENT/g).length, 2);
  assert.match(output, /DTSTART:20261024T080000Z/);
  assert.match(output, /DTSTART:20261031T090000Z/);
  assert.match(output, /UID:test-first@barberup/);
  assert.match(output, /DTEND:20261024T083000Z/);
  assert.ok(output.endsWith("END:VCALENDAR\r\n"));
  assert.ok(!output.includes("RRULE"));
});
test("calendar escapes text, folds UTF-8 safely and cannot inject event properties", () => {
  const service = "à💈".repeat(80) + ",;\\\r\nBEGIN:VEVENT";
  const output = createCalendar([{ ...first, service_name: service }]);
  assert.equal(output.match(/(?:^|\r\n)BEGIN:VEVENT/g).length, 1);
  for (const line of output.split("\r\n"))
    assert.ok(Buffer.byteLength(line) <= 75);
  const unfolded = output.replace(/\r\n /g, "");
  assert.ok(unfolded.includes("à💈".repeat(80)));
  assert.ok(unfolded.includes("\\,\\;\\\\\\nBEGIN:VEVENT"));
  assert.ok(!output.includes("\uFFFD"));
});
test("calendar rejects absent events and invalid duration", () => {
  assert.throws(() => createCalendar([]));
  assert.throws(() => createCalendar([{ ...first, end_at: first.start_at }]));
  assert.throws(() => createCalendar([{ ...first, start_at: "invalid" }]));
});

test("calendar preserves the configured brand spelling and case", () => {
  const output = createCalendar(
    [first],
    new Date("2026-10-20T12:00:00Z"),
    "bARber Àlfa",
  );
  assert.match(output, /SUMMARY:bARber Àlfa · Taglio/);
  assert.match(output, /PRODID:-\/\/bARber Àlfa\/\/Appuntamenti\/\/IT/);
  assert.match(output, /UID:test-first@barberup/);
});
