export function romeDay(date = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
export function maxBookingDate(date = new Date(), months = 6) {
  if (!Number.isInteger(months) || months < 1 || months > 120) throw new Error("INVALID_BOOKING_HORIZON");
  const [y, m, d] = romeDay(date).split("-").map(Number);
  const maxDay = new Date(Date.UTC(y, m + months, 0)).getUTCDate();
  return new Date(Date.UTC(y, m + months - 1, Math.min(d, maxDay)))
    .toISOString()
    .slice(0, 10);
}
export function romeLocalToISO(value) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value))
    throw new Error("INVALID_DATE");
  const target = Date.parse(value + "Z");
  let guess = target;
  for (let i = 0; i < 3; i++) {
    const p = Object.fromEntries(
      new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Rome",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23",
      })
        .formatToParts(new Date(guess))
        .filter((x) => x.type !== "literal")
        .map((x) => [x.type, x.value]),
    );
    const represented = Date.parse(
      p.year +
        "-" +
        p.month +
        "-" +
        p.day +
        "T" +
        p.hour +
        ":" +
        p.minute +
        ":" +
        p.second +
        "Z",
    );
    const next = guess + (target - represented);
    if (next === guess) return new Date(guess).toISOString();
    guess = next;
  }
  throw new Error("INVALID_DATE");
}
