import { createClient } from "@supabase/supabase-js";
export const supabase = createClient(
  "https://wrpwitehcikplsauiwmg.supabase.co",
  "sb_publishable_-HmWs8oJ651q7_Qqrd-rWA_KXwOYDgd",
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);
export async function result<T = any>(
  q: PromiseLike<{ data: any; error: { message: string } | null }>,
): Promise<T> {
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return data as T;
}
export function friendly(e: unknown) {
  let m = e instanceof Error ? e.message : String(e);
  for (const [k, v] of Object.entries({
    GUEST_NAME_REQUIRED:
      "Inserisci nome e cognome del cliente; il telefono è facoltativo.",
    INVALID_SERVICE:
      "Controlla nome, durata (multipli di 15 minuti) e prezzo del servizio.",
    BARBER_HAS_APPOINTMENTS:
      "Prima di eliminare questo barbiere, cancella o sposta i suoi appuntamenti futuri.",
    SETUP_REQUIRED:
      "Completa servizi, barbieri, orari, termini e regola di cancellazione prima di aprire le prenotazioni.",
    INVALID_DATE:
      "Questo orario non è valido nel fuso Europe/Rome. Scegline un altro.",
    SLOT_TAKEN: "Questo orario è stato appena prenotato. Scegline un altro.",
    LIMIT_FIVE:
      "Hai già 5 appuntamenti futuri. Cancella uno prima di prenotare.",
    PROFILE_REQUIRED: "Completa nome, cognome e telefono nel profilo.",
    TERMS_REQUIRED: "Leggi e accetta i termini aggiornati.",
    BOOKINGS_DISABLED: "Le prenotazioni non sono ancora aperte.",
    CANCELLATION_NOT_CONFIGURED:
      "La regola di cancellazione non è ancora configurata. Contatta il barbiere.",
    CANCELLATION_TOO_LATE:
      "Il termine per cancellare questo appuntamento è scaduto.",
    ACCESS_DENIED: "Non hai i permessi per questa operazione.",
    "Invalid login credentials": "Email o password non corrette.",
    "Email not confirmed": "Conferma la tua email prima di accedere.",
    "exclusion constraint": "Questo intervallo non è più disponibile.",
  }))
    if (m.includes(k)) return v;
  return /fetch|network|offline/i.test(m)
    ? "Connessione assente. Riprova quando sei online."
    : "Operazione non riuscita. Controlla i dati e riprova.";
}
export const euro = (n: number) =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(
    n,
  );
export const dateLabel = (s: string) =>
  new Intl.DateTimeFormat("it-IT", {
    dateStyle: "full",
    timeZone: "Europe/Rome",
  }).format(new Date(s));
export const timeLabel = (s: string) =>
  new Intl.DateTimeFormat("it-IT", {
    timeStyle: "short",
    timeZone: "Europe/Rome",
  }).format(new Date(s));
export const today = () =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
export type Row = Record<string, any>;
