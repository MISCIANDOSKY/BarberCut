function stamp(value) {
  return new Date(value).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}
function escape(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/\r\n|\r|\n/g, "\\n").replace(/,/g, "\\,").replace(/;/g, "\\;").replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
}
function fold(line) {
  const encoder = new TextEncoder();
  let part = "", size = 0;
  const parts = [];
  for (const char of line) {
    const bytes = encoder.encode(char).length;
    if (size + bytes > 75) { parts.push(part); part = " "; size = 1; }
    part += char; size += bytes;
  }
  parts.push(part);
  return parts.join("\r\n");
}
export function createCalendar(events, now = new Date()) {
  const unique = [...new Map(events.map((event) => [event.id, event])).values()];
  if (!unique.length) throw new Error("Nessun appuntamento da aggiungere.");
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//BarberUp//Appuntamenti//IT", "CALSCALE:GREGORIAN"];
  for (const event of unique) {
    if (!event.id || !Number.isFinite(Date.parse(event.start_at)) || !Number.isFinite(Date.parse(event.end_at)) || Date.parse(event.end_at) <= Date.parse(event.start_at)) throw new Error("Appuntamento non valido.");
    lines.push("BEGIN:VEVENT", "UID:" + escape(event.id) + "@barberup",
      "DTSTAMP:" + stamp(now), "DTSTART:" + stamp(event.start_at), "DTEND:" + stamp(event.end_at),
      "SUMMARY:" + escape("BarberUp · " + (event.service_name || "Appuntamento")),
      "DESCRIPTION:" + escape("Ricordati del tuo appuntamento! " + (event.service_name || "") + (event.barber_name ? "\nBarbiere: " + event.barber_name : "")),
      "BEGIN:VALARM", "TRIGGER:-PT1H", "ACTION:DISPLAY", "DESCRIPTION:Ricordati del tuo appuntamento!", "END:VALARM", "END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.map(fold).join("\r\n") + "\r\n";
}
