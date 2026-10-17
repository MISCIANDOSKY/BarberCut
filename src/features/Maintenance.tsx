import { useEffect, useState } from "react";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";

export default function Maintenance({
  notify,
}: {
  notify: (message: string) => void;
}) {
  const [status, setStatus] = useState<Row | null>(null);
  const [inactiveDays, setInactiveDays] = useState("120");
  const [appointmentDays, setAppointmentDays] = useState("40");
  const [disableInactive, setDisableInactive] = useState(true);
  const [deleteOld, setDeleteOld] = useState(true);
  const [requireApproval, setRequireApproval] = useState(true);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [error, setError] = useState("");
  async function load() {
    try {
      const data = await result<Row>(supabase.rpc("maintenance_status"));
      setStatus(data);
      setInactiveDays(String(data.settings.inactive_days));
      setAppointmentDays(String(data.settings.appointment_days));
      setDisableInactive(data.settings.disable_inactive);
      setDeleteOld(data.settings.delete_old_appointments);
      setRequireApproval(data.settings.require_user_approval);
    } catch (e) {
      setError(friendly(e));
    }
  }
  useEffect(() => {
    void load();
  }, []);
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const days = [Number(inactiveDays), Number(appointmentDays)];
    if (
      days.some(
        (value) => !Number.isInteger(value) || value < 1 || value > 36500,
      )
    ) {
      setError("Inserisci un numero intero di giorni tra 1 e 36500.");
      return;
    }
    setBusy(true);
    setError("");
    setFeedback("");
    try {
      await result(
        supabase.rpc("save_maintenance_with_registrations", {
          p_inactive_days: days[0],
          p_appointment_days: days[1],
          p_disable_inactive: disableInactive,
          p_delete_old: deleteOld,
          p_require_approval: requireApproval,
        }),
      );
      await load();
      setFeedback(
        "Impostazioni salvate. Verranno usate nella prossima manutenzione giornaliera.",
      );
      notify("Impostazioni di manutenzione salvate.");
    } catch (e) {
      setError(friendly(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <section>
      <h3>Manutenzione automatica giornaliera</h3>
      <p className="muted">
        Le operazioni attive vengono eseguite automaticamente ogni giorno. Puoi
        modificare i giorni e salvare le nuove soglie.
      </p>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <form onSubmit={save}>
        <h3>Iscrizione dei nuovi utenti</h3>
        <label className="check">
          <input type="checkbox" checked={requireApproval} disabled={busy || !status} onChange={(event) => setRequireApproval(event.target.checked)} />
          Richiedi approvazione per i nuovi utenti
        </label>
        <p className="muted">Se selezionata, i nuovi iscritti devono verificare l’email e poi essere approvati dall’admin o da un barbiere associato prima di prenotare. Se non selezionata, i nuovi account sono abilitati direttamente dopo la verifica email. Gli utenti già registrati mantengono il proprio stato.</p>
        <div className="maintenance-rule">
          <label className="check">
            <input
              type="checkbox"
              checked={disableInactive}
              disabled={busy || !status}
              onChange={(event) => setDisableInactive(event.target.checked)}
            />
            Disattiva account inattivi da
          </label>
          <label className="maintenance-days">
            <input
              aria-label="Giorni di inattività account"
              type="text"
              inputMode="numeric"
              pattern="[0-9]+"
              maxLength={5}
              required
              value={inactiveDays}
              disabled={busy || !status}
              onChange={(event) =>
                setInactiveDays(event.target.value.replace(/[^0-9]/g, ""))
              }
            />
            <span>giorni</span>
          </label>
        </div>
        <p className="muted">
          Solo account clienti, considerando anche l’uso di sessioni già aperte.
          Admin, barbieri e clienti con appuntamenti futuri sono esclusi. I dati
          degli account disattivati restano conservati.
        </p>
        <p className="muted">
          Prima della disattivazione vengono inviati avvisi email a 30, 15 e 7
          giorni. Basta completare un accesso o fare una prenotazione per far
          ripartire il conteggio. La disattivazione attende almeno sette giorni
          dall’ultimo avviso inviato.
        </p>
        <div className="maintenance-rule">
          <label className="check">
            <input
              type="checkbox"
              checked={deleteOld}
              disabled={busy || !status}
              onChange={(event) => setDeleteOld(event.target.checked)}
            />
            Elimina gli appuntamenti più vecchi di
          </label>
          <label className="maintenance-days">
            <input
              aria-label="Giorni di conservazione appuntamenti"
              type="text"
              inputMode="numeric"
              pattern="[0-9]+"
              maxLength={5}
              required
              value={appointmentDays}
              disabled={busy || !status}
              onChange={(event) =>
                setAppointmentDays(event.target.value.replace(/[^0-9]/g, ""))
              }
            />
            <span>giorni</span>
          </label>
        </div>
        <p className="muted">
          La soglia si calcola rispetto a oggi, nel fuso orario italiano. Gli
          appuntamenti più vecchi vengono eliminati definitivamente; quelli
          recenti e futuri restano disponibili.
        </p>
        <button className="primary" disabled={busy || !status}>
          {busy ? "Salvataggio…" : "Salva manutenzione"}
        </button>
      </form>
      {feedback && (
        <p className="notice" role="status">
          {feedback}
        </p>
      )}
      {status && (
        <div className="notice">
          {status.last_run ? (
            <p>
              Ultima esecuzione:{" "}
              {new Date(status.last_run.finished_at).toLocaleString("it-IT", {
                timeZone: "Europe/Rome",
              })}
              . Account disattivati: {status.last_run.disabled_accounts}.
              Appuntamenti eliminati: {status.last_run.deleted_appointments}.
            </p>
          ) : (
            <p>
              Manutenzione programmata. La prima esecuzione avverrà nel prossimo
              ciclo giornaliero.
            </p>
          )}
        </div>
      )}
      {!!status?.disabled_count && (
        <details className="notice">
          <summary>
            Account disattivati automaticamente ({status.disabled_count})
          </summary>
          <p className="muted">
            Puoi riattivare un account. La sua soglia di inattività ripartirà da
            oggi. Sono mostrati gli ultimi 100 account disattivati.
          </p>
          {status.disabled_accounts.map((account: Row) => (
            <div className="table-row" key={account.user_id}>
              <span>
                {account.first_name || "Cliente"} {account.last_name}
                <small>
                  {new Date(account.disabled_at).toLocaleDateString("it-IT", {
                    timeZone: "Europe/Rome",
                  })}
                </small>
              </span>
              <button
                className="secondary"
                disabled={busy}
                onClick={async () => {
                  setBusy(true);
                  setError("");
                  setFeedback("");
                  try {
                    await result(
                      supabase.rpc("reactivate_inactive_account", {
                        p_user: account.user_id,
                      }),
                    );
                    await load();
                    setFeedback("Account riattivato.");
                  } catch (e) {
                    setError(friendly(e));
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                Riattiva
              </button>
            </div>
          ))}
        </details>
      )}
    </section>
  );
}
