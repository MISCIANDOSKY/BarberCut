import { createCalendar } from "./calendar.mjs";
import type { CalendarEvent } from "./calendar.mjs";
export function downloadCalendar(event: CalendarEvent | CalendarEvent[]) {
  const events = Array.isArray(event) ? event : [event];
  const url = URL.createObjectURL(
    new Blob([createCalendar(events)], { type: "text/calendar;charset=utf-8" }),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download =
    events.length > 1 ? "BarberUp-appuntamenti.ics" : "BarberUp.ics";
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
}
