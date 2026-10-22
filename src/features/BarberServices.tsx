import { confirmInApp } from "../components/AppDialogs";
import { useEffect, useState } from "react";
import { Empty, Modal } from "../components/UI";
import { supabase, result, euro, friendly } from "../lib/api";
import type { Row } from "../lib/api";

export default function BarberServices({
  barberId,
  canEdit,
  notify,
  refresh,
}: {
  barberId: string;
  canEdit: boolean;
  notify: (message: string) => void;
  refresh: () => void;
}) {
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState<Row | null>(null);
  const [managing, setManaging] = useState<Row | null>(null);
  const [collaborators, setCollaborators] = useState<Row[]>([]);
  const [managementLoading, setManagementLoading] = useState(false);
  const [managementError, setManagementError] = useState("");
  async function load() {
    try {
      const links = (await result(
        supabase
          .from("barber_services")
          .select("service_id,active,staff_enabled,services(*)")
          .eq("barber_id", barberId),
      )) as Row[];
      setRows(
        links
          .map((link) =>
            link.services
              ? {
                  ...link.services,
                  link_active: link.active !== false,
                  staff_enabled: link.staff_enabled !== false,
                }
              : null,
          )
          .filter((service) => service && !service.deleted_at)
          .sort((a, b) => a.name.localeCompare(b.name, "it")),
      );
    } catch (error) {
      notify(friendly(error));
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    setRows([]);
    setLoading(true);
    load();
    setEditing(null);
    setManaging(null);
    setCollaborators([]);
  }, [barberId]);
  async function loadCollaborators(service: Row) {
    setManagementLoading(true);
    setManagementError("");
    try {
      setCollaborators(
        await result<Row[]>(
          supabase.rpc("service_collaborators", {
            p_source: barberId,
            p_service: service.id,
          }),
        ),
      );
    } catch (error) {
      setManagementError(friendly(error));
    } finally {
      setManagementLoading(false);
    }
  }
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || !canEdit) return;
    const values = new FormData(event.currentTarget);
    setBusy(true);
    try {
      await result(
        supabase.rpc("save_barber_service", {
          p_barber: barberId,
          p_service: editing?.id || null,
          p_name: values.get("name"),
          p_description: values.get("description"),
          p_duration: Number(values.get("duration")),
          p_price: Number(values.get("price")),
        }),
      );
      setEditing(null);
      await load();
      refresh();
      notify("Servizio salvato.");
    } catch (error) {
      notify(friendly(error));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <p className="muted">
        {canEdit
          ? "Gestisci i servizi della tua agenda. Le modifiche valgono per i tuoi servizi; gli altri barbieri mantengono i propri prezzi."
          : "Puoi disattivare o riattivare i servizi soltanto per la tua agenda. Per aggiungerli, modificarli o eliminarli rivolgiti all’admin o a un Barbiere Admin."}
      </p>
      {canEdit && (
        <button
          className="primary"
          onClick={() => setEditing({})}
          disabled={busy}
        >
          ＋ Aggiungi servizio
        </button>
      )}
      {loading ? (
        <p role="status">Caricamento servizi…</p>
      ) : !rows.length ? (
        <Empty>Non hai ancora servizi associati alla tua agenda.</Empty>
      ) : (
        rows.map((service) => (
          <article className="table-row" key={service.id}>
            <span>
              <strong>{service.name}</strong>
              <small>
                {service.duration_minutes} minuti · {euro(service.price)}
                {!service.active
                  ? " · Disattivato dall’admin"
                  : !service.staff_enabled
                    ? " · Disattivato dal titolare"
                    : !service.link_active
                      ? " · Disattivato per te"
                      : ""}
              </small>
              {service.description && <small>{service.description}</small>}
            </span>
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: ".75rem",
              }}
            >
              <button
                className="text"
                disabled={busy}
                onClick={async () => {
                  if (busy) return;
                  if (!service.active || !service.staff_enabled) {
                    notify("Chiedi al tuo titolare di riattivare il servizio.");
                    return;
                  }
                  setBusy(true);
                  try {
                    await result(
                      supabase.rpc("set_barber_service_active", {
                        p_barber: barberId,
                        p_service: service.id,
                        p_active: !service.link_active,
                      }),
                    );
                    await load();
                    refresh();
                    notify(
                      service.link_active
                        ? "Servizio disattivato per la tua agenda."
                        : "Servizio riattivato per la tua agenda.",
                    );
                  } catch (error) {
                    notify(friendly(error));
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                {service.active && service.staff_enabled && service.link_active
                  ? "Disattiva per me"
                  : "Riattiva per me"}
              </button>
              {canEdit && (
                <>
                  <button
                    className="text"
                    disabled={busy}
                    onClick={() => {
                      setManaging(service);
                      setCollaborators([]);
                      void loadCollaborators(service);
                    }}
                  >
                    Gestisci per collaboratori
                  </button>
                  <button
                    className="text"
                    disabled={busy}
                    onClick={() => setEditing(service)}
                  >
                    Modifica
                  </button>{" "}
                  <button
                    className="text danger-text"
                    disabled={busy}
                    onClick={async () => {
                      if (
                        !(await confirmInApp(
                          "Sei sicuro di voler eliminare il servizio «" +
                            service.name +
                            "» dalla tua agenda? Gli appuntamenti già presenti saranno conservati.",
                        ))
                      )
                        return;
                      setBusy(true);
                      try {
                        await result(
                          supabase.rpc("remove_barber_service", {
                            p_barber: barberId,
                            p_service: service.id,
                          }),
                        );
                        await load();
                        refresh();
                        notify("Servizio eliminato dalla tua agenda.");
                      } catch (error) {
                        notify(friendly(error));
                      } finally {
                        setBusy(false);
                      }
                    }}
                  >
                    Elimina
                  </button>
                </>
              )}
            </div>
          </article>
        ))
      )}
      {canEdit && managing && (
        <Modal
          wide
          title="Gestisci per collaboratori"
          close={() => {
            if (!busy) setManaging(null);
          }}
        >
          <h3>{managing.name}</h3>
          <p className="muted">
            Spunta un collaboratore per abilitare il servizio nella sua agenda.
            Togli la spunta per impedirgli di offrirlo: potrà riattivarlo
            soltanto il titolare. Le modifiche vengono salvate subito.
          </p>
          {!managing.active && (
            <p className="notice">
              Il servizio è disattivato globalmente dall’admin e resta
              indisponibile anche per i collaboratori selezionati.
            </p>
          )}
          {managementError && (
            <p className="form-error" role="alert">
              {managementError}
            </p>
          )}
          {managementLoading ? (
            <p role="status">Caricamento collaboratori…</p>
          ) : !collaborators.length && !managementError ? (
            <Empty>Non ci sono altri collaboratori attivi.</Empty>
          ) : (
            collaborators.map((collaborator) => (
              <label className="check" key={collaborator.barber_id}>
                <input
                  type="checkbox"
                  checked={collaborator.enabled}
                  disabled={busy}
                  onChange={async (event) => {
                    const enabled = event.currentTarget.checked;
                    setBusy(true);
                    setManagementError("");
                    try {
                      await result(
                        supabase.rpc("set_collaborator_service", {
                          p_source: barberId,
                          p_service: managing.id,
                          p_barber: collaborator.barber_id,
                          p_enabled: enabled,
                        }),
                      );
                      await loadCollaborators(managing);
                      refresh();
                      notify(
                        enabled
                          ? "Servizio abilitato per il collaboratore."
                          : "Servizio disattivato per il collaboratore.",
                      );
                    } catch (error) {
                      setManagementError(friendly(error));
                    } finally {
                      setBusy(false);
                    }
                  }}
                />
                <span>
                  {collaborator.barber_name}
                  {collaborator.enabled && !collaborator.personally_active && (
                    <small>Disattivato personalmente dal collaboratore</small>
                  )}
                </span>
              </label>
            ))
          )}
        </Modal>
      )}
      {canEdit && editing && (
        <Modal
          title={editing.id ? "Modifica servizio" : "Nuovo servizio"}
          close={() => {
            if (!busy) setEditing(null);
          }}
        >
          <form onSubmit={save}>
            <label>
              Nome
              <input
                name="name"
                defaultValue={editing.name || ""}
                required
                maxLength={160}
              />
            </label>
            <label>
              Descrizione (facoltativa)
              <textarea
                name="description"
                defaultValue={editing.description || ""}
                rows={3}
              />
            </label>
            <div className="two">
              <label>
                Durata (minuti)
                <input
                  type="number"
                  name="duration"
                  min="15"
                  max="480"
                  step="15"
                  defaultValue={editing.duration_minutes || 30}
                  required
                />
              </label>
              <label>
                Prezzo (€)
                <input
                  type="number"
                  name="price"
                  min="0"
                  max="999999.99"
                  step=".01"
                  defaultValue={editing.price ?? ""}
                  required
                />
              </label>
            </div>
            <button className="primary" disabled={busy}>
              {busy ? "Salvataggio…" : "Salva servizio"}
            </button>
          </form>
        </Modal>
      )}
    </>
  );
}
