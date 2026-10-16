import { useEffect, useState } from "react";
import { Empty, Modal } from "../components/UI";
import { supabase, result } from "../lib/api";
import type { Row } from "../lib/api";
export default function Admin({
  section,
  notify,
  refresh,
}: {
  section: string;
  notify: (s: string) => void;
  refresh: () => void;
}) {
  const [editing, setEditing] = useState<Row | null>(null);
  const [rows, setRows] = useState<Row[]>([]),
    [users, setUsers] = useState<Row[]>([]),
    [services, setServices] = useState<Row[]>([]),
    [barbers, setBarbers] = useState<Row[]>([]),
    [settings, setSettings] = useState<Row | null>(null),
    [busy, setBusy] = useState(false);
  async function load() {
    try {
      const table =
        section === "Barbieri"
          ? "barbers"
          : section === "Utenti"
            ? "user_roles"
            : section === "Servizi"
              ? "services"
              : section === "Termini"
                ? "terms_versions"
                : null;
      if (table)
        setRows((await result(supabase.from(table).select("*"))) as Row[]);
      if (section === "Utenti" || section === "Barbieri")
        setUsers(
          (await result(supabase.from("profiles").select("*"))) as Row[],
        );
      if (section === "Servizi") {
        setServices(
          (await result(supabase.from("services").select("*"))) as Row[],
        );
        setBarbers(
          (await result(supabase.from("barbers").select("*"))) as Row[],
        );
      }
      if (section === "Configurazione")
        setSettings(
          (await result(
            supabase.from("app_settings").select("*").single(),
          )) as Row,
        );
    } catch {
      notify("Non riesco a caricare i dati amministrativi.");
    }
  }
  useEffect(() => {
    load();
  }, [section]);
  async function run(fn: () => Promise<unknown>) {
    setBusy(true);
    try {
      await fn();
      notify("Modifiche salvate.");
      load();
      refresh();
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
    } finally {
      setBusy(false);
    }
  }
  if (section === "Configurazione")
    return settings ? (
      <form
        onSubmit={(e) => {
          e.preventDefault();
          const v = new FormData(e.currentTarget);
          run(() =>
            result(
              supabase
                .from("app_settings")
                .update({
                  shop_name: v.get("name"),
                  accent: v.get("accent"),
                  cancellation_hours:
                    v.get("hours") === "" ? null : Number(v.get("hours")),
                  bookings_enabled: v.get("enabled") === "on",
                  account_deletion_enabled: v.get("deletion") === "on",
                })
                .eq("id", true),
            ),
          );
        }}
      >
        <label>
          Nome attività
          <input name="name" defaultValue={settings.shop_name} required />
        </label>
        <label>
          Colore principale
          <input type="color" name="accent" defaultValue={settings.accent} />
        </label>
        <label>
          Cancellazione: ore minime prima dell’appuntamento
          <input
            type="number"
            min="0"
            step="1"
            name="hours"
            defaultValue={settings.cancellation_hours ?? ""}
          />
        </label>
        <p className="muted">
          Lascia vuoto finché la regola non è decisa. Zero permette di
          cancellare fino all’inizio.
        </p>
        <label className="check">
          <input
            type="checkbox"
            name="enabled"
            defaultChecked={settings.bookings_enabled}
          />
          Apri le prenotazioni online
        </label>
        <p className="notice">
          Prima di aprire: configura barbieri, servizi, associazioni, orari e
          pubblica i termini approvati. Fuso orario: Europe/Rome.
        </p>
        <label className="check">
          <input
            type="checkbox"
            name="deletion"
            defaultChecked={settings.account_deletion_enabled}
          />
          Abilita eliminazione account verificata via email
        </label>
        <p className="muted">
          Attiva solo dopo aver definito la politica di conservazione: profilo
          eliminato, appuntamenti futuri cancellati e storico anonimizzato.
          L’ultimo admin non può eliminarsi.
        </p>
        <button className="primary" disabled={busy}>
          Salva configurazione
        </button>
      </form>
    ) : (
      <Empty>Caricamento…</Empty>
    );
  if (section === "Manutenzione")
    return (
      <>
        <h3>Dati e manutenzione</h3>
        <p>
          La pulizia automatica degli appuntamenti e degli account è disattivata
          finché non viene approvata una politica di conservazione.
        </p>
        <button
          className="secondary"
          disabled={busy}
          onClick={() =>
            run(async () => {
              const tables = [
                "profiles",
                "user_roles",
                "barbers",
                "services",
                "barber_services",
                "working_hours",
                "schedule_exceptions",
                "calendar_entries",
                "terms_versions",
                "terms_acceptances",
                "notifications",
                "app_settings",
              ];
              const data: Row = { exported_at: new Date().toISOString() };
              for (const t of tables)
                data[t] = await result(supabase.from(t).select("*"));
              const u = URL.createObjectURL(
                new Blob([JSON.stringify(data, null, 2)], {
                  type: "application/json",
                }),
              );
              const a = document.createElement("a");
              a.href = u;
              a.download =
                "barbercut-export-" +
                new Date().toISOString().slice(0, 10) +
                ".json";
              a.click();
              setTimeout(() => URL.revokeObjectURL(u), 1000);
            })
          }
        >
          Esporta dati applicativi JSON
        </button>
        <p className="muted">
          L’esportazione contiene dati personali e non include gli account Auth:
          non è un backup completo del database. Conservala in un luogo
          protetto.
        </p>
      </>
    );
  return (
    <>
      {editing && (
        <Modal
          title={
            section === "Termini"
              ? "Termini " + editing.version
              : "Modifica " + (editing.name || "")
          }
          close={() => setEditing(null)}
        >
          {section === "Termini" ? (
            <p className="legal">{editing.body}</p>
          ) : (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                const v = new FormData(e.currentTarget);
                run(async () => {
                  await result(
                    supabase
                      .from(section === "Servizi" ? "services" : "barbers")
                      .update(
                        section === "Servizi"
                          ? {
                              name: v.get("name"),
                              description: v.get("description"),
                              duration_minutes: Number(v.get("duration")),
                              price: Number(v.get("price")),
                            }
                          : {
                              name: v.get("name"),
                              user_id: v.get("user") || null,
                            },
                      )
                      .eq("id", editing.id),
                  );
                  setEditing(null);
                });
              }}
            >
              <label>
                Nome
                <input name="name" defaultValue={editing.name} required />
              </label>
              {section === "Servizi" ? (
                <>
                  <label>
                    Descrizione
                    <input
                      name="description"
                      defaultValue={editing.description}
                    />
                  </label>
                  <div className="two">
                    <label>
                      Durata
                      <input
                        name="duration"
                        type="number"
                        min="15"
                        max="480"
                        step="15"
                        defaultValue={editing.duration_minutes}
                        required
                      />
                    </label>
                    <label>
                      Prezzo
                      <input
                        name="price"
                        type="number"
                        min="0"
                        step=".01"
                        defaultValue={editing.price}
                        required
                      />
                    </label>
                  </div>
                </>
              ) : (
                <label>
                  Account
                  <select name="user" defaultValue={editing.user_id || ""}>
                    <option value="">Nessuno</option>
                    {users.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.first_name} {u.last_name}
                      </option>
                    ))}
                  </select>
                </label>
              )}
              <button className="primary" disabled={busy}>
                Salva
              </button>
            </form>
          )}
        </Modal>
      )}
      {section === "Utenti"
        ? rows.map((r) => {
            const p = users.find((u) => u.id === r.user_id);
            return (
              <article className="table-row" key={r.user_id}>
                <span>
                  {p?.first_name || "Account"} {p?.last_name}
                  <small>{r.user_id}</small>
                </span>
                <select
                  aria-label={"Ruolo di " + (p?.first_name || r.user_id)}
                  value={r.role}
                  disabled={busy}
                  onChange={(e) => {
                    const role = e.target.value;
                    if (
                      confirm(
                        "Confermi il ruolo " + role + " per questo account?",
                      )
                    )
                      run(() =>
                        result(
                          supabase
                            .from("user_roles")
                            .update({ role })
                            .eq("user_id", r.user_id),
                        ),
                      );
                  }}
                >
                  <option value="client">Cliente</option>
                  <option value="barber">Barbiere</option>
                  <option value="admin">Admin</option>
                </select>
              </article>
            );
          })
        : rows.map((r) => (
            <article className="table-row" key={r.id}>
              <span>
                <strong>{r.name || r.version}</strong>
                <button className="text" onClick={() => setEditing(r)}>
                  {section === "Termini" ? "Leggi testo" : "Modifica"}
                </button>
                <small>
                  {section === "Servizi"
                    ? r.duration_minutes + " min · " + r.price + " €"
                    : section === "Barbieri"
                      ? r.user_id || "Account da associare"
                      : r.published
                        ? "Pubblicato"
                        : "Bozza"}
                </small>
              </span>
              {section === "Termini" ? (
                <button
                  className="secondary"
                  disabled={busy || r.published}
                  onClick={() => {
                    if (
                      confirm(
                        "Confermi che questo testo è approvato e pronto per essere pubblicato?",
                      )
                    )
                      run(() =>
                        result(supabase.rpc("publish_terms", { p_id: r.id })),
                      );
                  }}
                >
                  {r.published ? "Pubblicato" : "Pubblica"}
                </button>
              ) : (
                <button
                  className="text"
                  disabled={busy}
                  onClick={() =>
                    run(() =>
                      result(
                        supabase
                          .from(section === "Servizi" ? "services" : "barbers")
                          .update({ active: !r.active })
                          .eq("id", r.id),
                      ),
                    )
                  }
                >
                  {r.active ? "Disattiva" : "Riattiva"}
                </button>
              )}
            </article>
          ))}
      {section === "Barbieri" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const v = new FormData(e.currentTarget);
            run(() =>
              result(
                supabase.from("barbers").insert({
                  name: v.get("name"),
                  user_id: v.get("user") || null,
                }),
              ),
            );
          }}
        >
          <h3>Aggiungi barbiere</h3>
          <label>
            Nome in agenda
            <input name="name" required />
          </label>
          <label>
            Account associato
            <select name="user">
              <option value="">Da associare</option>
              {users.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.first_name} {u.last_name} · {u.id.slice(0, 8)}
                </option>
              ))}
            </select>
          </label>
          <p className="muted">
            Assegna anche il ruolo Barbiere nella sezione Utenti.
          </p>
          <button className="primary" disabled={busy}>
            Aggiungi barbiere
          </button>
        </form>
      )}
      {section === "Servizi" && (
        <>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const v = new FormData(e.currentTarget);
              run(() =>
                result(
                  supabase.from("services").insert({
                    name: v.get("name"),
                    description: v.get("description"),
                    duration_minutes: Number(v.get("duration")),
                    price: Number(v.get("price")),
                  }),
                ),
              );
            }}
          >
            <h3>Nuovo servizio</h3>
            <label>
              Nome
              <input name="name" required />
            </label>
            <label>
              Descrizione
              <input name="description" />
            </label>
            <div className="two">
              <label>
                Durata (minuti)
                <input
                  name="duration"
                  type="number"
                  min="15"
                  max="480"
                  step="15"
                  required
                />
              </label>
              <label>
                Prezzo (€)
                <input name="price" type="number" min="0" step=".01" required />
              </label>
            </div>
            <button className="primary" disabled={busy}>
              Crea servizio
            </button>
          </form>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const v = new FormData(e.currentTarget);
              run(() =>
                result(
                  supabase.from("barber_services").upsert({
                    barber_id: v.get("barber"),
                    service_id: v.get("service"),
                  }),
                ),
              );
            }}
          >
            <h3>Associa servizio al barbiere</h3>
            <label>
              Barbiere
              <select name="barber" required>
                {barbers.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Servizio
              <select name="service" required>
                {services.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </label>
            <button className="secondary" disabled={busy}>
              Associa
            </button>
          </form>
        </>
      )}
      {section === "Termini" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const v = new FormData(e.currentTarget);
            run(() =>
              result(
                supabase
                  .from("terms_versions")
                  .insert({ version: v.get("version"), body: v.get("body") }),
              ),
            );
          }}
        >
          <h3>Nuova versione</h3>
          <p className="notice">
            Inserisci un testo approvato dal titolare. Non viene generato
            automaticamente alcun testo legale.
          </p>
          <label>
            Versione
            <input name="version" placeholder="Es. 1.0" required />
          </label>
          <label>
            Testo
            <textarea name="body" rows={12} required />
          </label>
          <button className="primary" disabled={busy}>
            Salva bozza
          </button>
        </form>
      )}
    </>
  );
}
