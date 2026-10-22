import BrandNameSettings from "./BrandNameSettings";
import { getBrandName } from "../lib/branding";
import LogAccess from "./LogAccess";
import AdminServiceManagement from "./AdminServiceManagement";
import BookingHorizon from "./BookingHorizon";
import BarberAddress from "./BarberAddress";
import { AppPicker } from "../components/AppPicker";
import { AppSelect } from "../components/AppSelect";
import { confirmInApp } from "../components/AppDialogs";
import { useEffect, useState } from "react";
import { Empty, Modal } from "../components/UI";
import { supabase, result } from "../lib/api";
import type { Row } from "../lib/api";
import Maintenance from "./Maintenance";
import RecurringPolicy from "./RecurringPolicy";
import { RegistrationChoice } from "./RegistrationPolicy";
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
  const [managingService, setManagingService] = useState<Row | null>(null);
  const [requireApproval, setRequireApproval] = useState(true);
  const [rows, setRows] = useState<Row[]>([]),
    [users, setUsers] = useState<Row[]>([]),
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
      if (table) {
        const query = supabase.from(table).select("*");
        setRows(
          (await result(
            table === "services" || table === "barbers"
              ? query.is("deleted_at", null)
              : query,
          )) as Row[],
        );
      }
      if (section === "Utenti" || section === "Barbieri")
        setUsers(
          (await result(supabase.from("profiles").select("*"))) as Row[],
        );
      if (section === "Servizi" || section === "Barbieri") {
        setBarbers(
          (await result(
            supabase.from("barbers").select("*").is("deleted_at", null),
          )) as Row[],
        );
      }
      if (section === "Configurazione" || section === "Manutenzione") {
        const config = await result<Row>(
          supabase.from("app_settings").select("*").single(),
        );
        setSettings(config);
        setRequireApproval(config.require_user_approval !== false);
      }
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
      await load();
      refresh();
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
    } finally {
      setBusy(false);
    }
  }
  function availableUsers(exceptBarberId?: string) {
    return users.filter(
      (account) =>
        !barbers.some(
          (barber) =>
            barber.user_id === account.id && barber.id !== exceptBarberId,
        ),
    );
  }
  if (section === "Configurazione")
    return settings ? (
      <>
        <BarberAddress
          address={settings.shop_address || ""}
          revision={settings.address_revision || 0}
          refresh={() => {
            void load();
            refresh();
          }}
        />
        <RecurringPolicy
          settings={settings}
          refresh={() => {
            void load();
            refresh();
          }}
        />
        <LogAccess refresh={refresh} />
        <BrandNameSettings />
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const v = new FormData(e.currentTarget);
            run(() =>
              result(
                supabase
                  .from("app_settings")
                  .update({
                    accent: v.get("accent"),
                    cancellation_hours:
                      v.get("hours") === "" ? null : Number(v.get("hours")),
                    require_user_approval: requireApproval,
                    bookings_enabled: v.get("enabled") === "on",
                    account_deletion_enabled: v.get("deletion") === "on",
                  })
                  .eq("id", true),
              ),
            );
          }}
        >
          <label>
            Colore principale
            <AppPicker
              type="color"
              name="accent"
              defaultValue={settings.accent}
            />
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
          <RegistrationChoice
            required={requireApproval}
            disabled={busy}
            onChange={setRequireApproval}
          />
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
      </>
    ) : (
      <Empty>Caricamento…</Empty>
    );
  if (section === "Manutenzione")
    return (
      <>
        {settings ? (
          <BookingHorizon
            settings={settings}
            refresh={() => {
              void load();
              refresh();
            }}
          />
        ) : (
          <Empty>Caricamento impostazioni prenotazioni…</Empty>
        )}
        <Maintenance notify={notify} />
        <h3>Esportazione dati</h3>
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
                getBrandName().replace(/[^\p{L}\p{N} _-]/gu, "_") +
                "-export-" +
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
      {section === "Servizi" && managingService && (
        <AdminServiceManagement
          service={managingService}
          close={() => setManagingService(null)}
          onSaved={() => {
            void load();
            refresh();
          }}
        />
      )}
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
                    <textarea
                      name="description"
                      defaultValue={editing.description || ""}
                      rows={3}
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
                  <AppSelect name="user" defaultValue={editing.user_id || ""}>
                    <option value="">Nessuno</option>
                    {availableUsers(editing.id).map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.first_name} {u.last_name}
                      </option>
                    ))}
                  </AppSelect>
                </label>
              )}
              <button className="primary" disabled={busy}>
                Salva
              </button>
            </form>
          )}
        </Modal>
      )}
      {section === "Utenti" && (
        <p className="muted">
          Registra l’account Barberia come cliente e assegna qui il ruolo
          Barberia per aprire direttamente le agende dei barbieri. I nuovi
          barbieri ricevono automaticamente il ruolo Barbiere. Solo l’admin può
          assegnare Barbiere Admin da questo menu.
        </p>
      )}
      {section === "Utenti"
        ? rows.map((r) => {
            const p = users.find((u) => u.id === r.user_id);
            const currentRoleLabel =
              r.role === "barber_admin"
                ? "Barbiere Admin"
                : r.role === "barber"
                  ? "Barbiere"
                  : r.role === "admin"
                    ? "Admin"
                    : r.role === "shop"
                      ? "Barberia"
                      : "Cliente";
            return (
              <article className="table-row" key={r.user_id}>
                <span>
                  {p?.first_name || "Account"} {p?.last_name}
                  <small>{currentRoleLabel}</small>
                </span>
                <AppSelect
                  aria-label={"Ruolo di " + (p?.first_name || r.user_id)}
                  value={r.role}
                  disabled={busy}
                  onChange={async (e) => {
                    const role = e.target.value;
                    const roleLabel =
                      role === "barber_admin"
                        ? "Barbiere Admin"
                        : role === "barber"
                          ? "Barbiere"
                          : role === "admin"
                            ? "Admin"
                            : role === "shop"
                              ? "Barberia"
                              : "Cliente";
                    if (
                      await confirmInApp(
                        "Confermi il ruolo " +
                          roleLabel +
                          " per questo account?",
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
                  <option value="barber_admin">Barbiere Admin</option>
                  <option value="shop">Barberia</option>
                  <option value="admin">Admin</option>
                </AppSelect>
              </article>
            );
          })
        : rows.map((r) => (
            <article className="table-row" key={r.id}>
              <span>
                <strong>{r.name || r.version}</strong>
                {section === "Termini" && (
                  <button className="text" onClick={() => setEditing(r)}>
                    Leggi testo
                  </button>
                )}
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
                  onClick={async () => {
                    if (
                      await confirmInApp(
                        "Confermi che questo testo è approvato e pronto per essere pubblicato? Tutti gli utenti, compresi gli amministratori e i barbieri, dovranno accettare la nuova versione per continuare a usare l’app.",
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
                <div
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "stretch",
                    gap: ".75rem",
                  }}
                >
                  <button
                    className="text"
                    disabled={busy}
                    onClick={() => setEditing(r)}
                  >
                    Modifica
                  </button>
                  {section === "Servizi" ? (
                    <button
                      className="text"
                      disabled={busy}
                      onClick={() => setManagingService(r)}
                    >
                      Gestisci
                    </button>
                  ) : (
                    <button
                      className="text"
                      disabled={busy}
                      onClick={() =>
                        run(() =>
                          result(
                            supabase
                              .from("barbers")
                              .update({ active: !r.active })
                              .eq("id", r.id),
                          ),
                        )
                      }
                    >
                      {r.active ? "Disattiva" : "Riattiva"}
                    </button>
                  )}

                  <button
                    className="text danger-text"
                    disabled={busy}
                    onClick={async () => {
                      const kind = section === "Servizi" ? "service" : "barber";
                      if (
                        !(await confirmInApp(
                          section === "Servizi"
                            ? "Sei sicuro di voler eliminare il servizio «" +
                                r.name +
                                "»? Verrà rimosso dal catalogo; gli appuntamenti già presenti saranno conservati."
                            : "Eliminare " +
                                r.name +
                                "? La voce verrà rimossa dagli elenchi; i dati degli appuntamenti saranno conservati.",
                        ))
                      )
                        return;
                      run(() =>
                        result(
                          supabase.rpc("admin_delete_resource", {
                            p_kind: kind,
                            p_id: r.id,
                          }),
                        ),
                      );
                    }}
                  >
                    Elimina
                  </button>
                </div>
              )}
            </article>
          ))}
      {section === "Barbieri" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const form = e.currentTarget;
            const v = new FormData(form);
            run(async () => {
              await result(
                supabase.from("barbers").insert({
                  name: v.get("name"),
                  user_id: v.get("user") || null,
                }),
              );
              form.reset();
            });
          }}
        >
          <h3>Aggiungi barbiere</h3>
          <label>
            Nome in agenda
            <input name="name" required />
          </label>
          <label>
            Account associato
            <AppSelect name="user" required>
              <option value="">Scegli un account registrato</option>
              {availableUsers().map((u) => (
                <option key={u.id} value={u.id}>
                  {u.first_name} {u.last_name} · {u.id.slice(0, 8)}
                </option>
              ))}
            </AppSelect>
          </label>
          <p className="muted">
            Il ruolo Barbiere viene assegnato automaticamente all’account
            associato. I servizi attivi degli altri barbieri attivi vengono
            associati automaticamente. Vengono copiati anche gli orari
            settimanali di un barbiere di riferimento: prima la tua agenda, se
            presente, altrimenti un Barbiere Admin attivo. Il nuovo barbiere
            potrà soltanto disattivarli o riattivarli per sé da Servizi e
            prezzi. Per consentire anche aggiunta, modifica ed eliminazione,
            assegna il ruolo Barbiere Admin da Utenti. Eliminando il barbiere,
            l’account torna Cliente e può essere nuovamente associato.
          </p>
          {!availableUsers().length && (
            <p className="muted">
              Non ci sono account disponibili. Registra un nuovo account oppure
              modifica o elimina l’associazione di un barbiere esistente.
            </p>
          )}
          <button
            className="primary"
            disabled={busy || !availableUsers().length}
          >
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
