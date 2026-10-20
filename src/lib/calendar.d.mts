export type CalendarEvent = {
  id: string;
  start_at: string;
  end_at: string;
  service_name?: string;
  barber_name?: string;
};
export function createCalendar(events: CalendarEvent[], now?: Date): string;
