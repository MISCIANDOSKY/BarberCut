import { getBrandName } from "./branding";
import { createCalendar } from "./calendar.mjs";
import type { Row } from "./api";
export function downloadCalendar(event: Row | Row[]) {
  const events = Array.isArray(event) ? event : [event];
  const url = URL.createObjectURL(
    new Blob(
      [
        createCalendar(
          events.map((item) => ({
            id: item.id,
            start_at: item.start_at,
            end_at: item.end_at,
            service_name: item.service_name,
            barber_name: item.barber_name,
          })),
          new Date(),
          getBrandName(),
        ),
      ],
      { type: "text/calendar;charset=utf-8" },
    ),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download =
    getBrandName().replace(/[^\p{L}\p{N} _-]/gu,"_") + (events.length > 1 ? "-appuntamenti.ics" : ".ics");
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
}
