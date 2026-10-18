import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { clearPasswordProof } from "../lib/passwordProof";
import { Empty, Field } from "../components/UI";
import { supabase, result, dateLabel, timeLabel, euro } from "../lib/api";
import type { Row } from "../lib/api";
import { downloadCalendar } from "./Booking";
export function Appointments({
  rows,
  reload,
  notify,
  settings,
}: {
  rows: Row[];
  reload: () => void;
  notify: (s: string) => void;
  settings: Row;
}) {
  const [busy, setBusy] = useState(""),
    [confirm, setConfirm] = useState("");
  async function cancel(id: string) {
    setBusy(id);
    try {
      await result(supabase.rpc("cancel_appointment", { p_id: id }));
      notify("Prenotazione cancellata.");
      reload();
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
    } finally {
      setBusy("");
      setConfirm("");
    }
  }
  return (
    <>
      {!rows.length && (
        <Empty>
          Non hai ancora appuntamenti. Il prossimo momento per te ti aspetta.
        </Empty>
      )}
      {rows.map((e) => (
        <article className="appointment" key={e.id}>
          <span className="eyebrow">IL TUO PROSSIMO APPUNTAMENTO</span>
          <h3>{e.service_name}</h3>
          <p>{dateLabel(e.start_at)}</p>
          <div className="appointment-time">
            {timeLabel(e.start_at)} <small>{euro(e.price)}</small>
          </div>
          <button className="text" onClick={() => downloadCalendar(e)}>
            Aggiungi al calendario
          </button>
          {settings.cancellation_hours === null ? (
            <p className="muted">
              Per cancellare, contatta il barbiere: le condizioni sono in fase
              di configurazione.
            </p>
          ) : confirm === e.id ? (
            <div className="notice">
              <p>Vuoi cancellare questo appuntamento?</p>
              <button
                className="danger"
                disabled={!!busy}
                onClick={() => cancel(e.id)}
              >
                {busy ? "Attendi…" : "Conferma cancellazione"}
              </button>
              <button className="text" onClick={() => setConfirm("")}>
                Mantieni appuntamento
              </button>
            </div>
          ) : (
            <button
              className="text danger-text"
              onClick={() => setConfirm(e.id)}
            >
              Cancella prenotazione
            </button>
          )}
        </article>
      ))}
    </>
  );
}
export function Profile({
  user,
  profile,
  notify,
  reload,
  deletionEnabled,
  addressEditor,
  registrationEditor,
}: {
  user: Row;
  profile: Row;
  notify: (s: string) => void;
  reload: () => void;
  deletionEnabled: boolean;
  addressEditor?: ReactNode;
  registrationEditor?: ReactNode;
}) {
  const [first, setFirst] = useState(profile.first_name),
    [last, setLast] = useState(profile.last_name),
    [phone, setPhone] = useState(profile.phone),
    [busy, setBusy] = useState(false),
    [loggingOut, setLoggingOut] = useState(false);
  return (
    <>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          try {
            await result(
              supabase
                .from("profiles")
                .update({ first_name: first, last_name: last, phone })
                .eq("id", user.id),
            );
            notify("Profilo aggiornato.");
            reload();
          } catch {
            notify("Impossibile salvare il profilo.");
          } finally {
            setBusy(false);
          }
        }}
      >
        <div className="two">
          <Field
            label="Nome"
            name="given-name"
            value={first}
            onChange={setFirst}
          />
          <Field
            label="Cognome"
            name="family-name"
            value={last}
            onChange={setLast}
          />
        </div>
        <Field
          label="Telefono"
          type="tel"
          name="tel"
          value={phone}
          onChange={setPhone}
        />
        <label>
          Email
          <input value={user.email || ""} readOnly />
        </label>
        <button className="primary" disabled={busy}>
          {busy ? "Salvataggio…" : "Salva profilo"}
        </button>
      </form>
      <div style={{ marginTop: ".75rem", marginBottom: ".75rem" }}>
        <button
          type="button"
          className="secondary"
          disabled={busy || loggingOut}
          style={{ width: "100%" }}
          onClick={async () => {
            if (loggingOut) return;
            setLoggingOut(true);
            try {
              const { error } = await supabase.auth.signOut({ scope: "local" });
              if (error) throw error;
              clearPasswordProof();
              notify("Hai effettuato l’uscita dal tuo account.");
              reload();
            } catch {
              notify("Non riesco a uscire dall’account. Riprova.");
            } finally {
              setLoggingOut(false);
            }
          }}
        >
          {loggingOut ? "Uscita in corso…" : "Esci dal tuo account"}
        </button>
      </div>
      <button
        className="text"
        onClick={async () => {
          await supabase.auth.resetPasswordForEmail(user.email, {
            redirectTo: location.origin + import.meta.env.BASE_URL,
          });
          notify(
            "Controlla l’email per cambiare la password. Controlla anche le cartelle Spam e Posta indesiderata.",
          );
        }}
      >
        Cambia password
      </button>
      {registrationEditor}
      {addressEditor}
      <DeleteAccount
        email={user.email}
        enabled={deletionEnabled}
        notify={notify}
        reload={reload}
      />
    </>
  );
}
export function Notifications({
  rows,
  reload,
  notify,
  userId,
}: {
  rows: Row[];
  reload: () => void;
  notify: (s: string) => void;
  userId: string;
}) {
  useEffect(() => {
    if (rows.some((n) => !n.read_at))
      result(
        supabase
          .from("notifications")
          .update({ read_at: new Date().toISOString() })
          .eq("user_id", userId)
          .is("read_at", null),
      )
        .then(reload)
        .catch(() =>
          notify("Impossibile aggiornare la lettura delle notifiche."),
        );
  }, [rows, userId]);
  return (
    <>
      {!rows.length && (
        <Empty>
          Sei aggiornato. Qui troverai le novità sui tuoi appuntamenti.
        </Empty>
      )}
      {rows.some((n) => !n.read_at) && (
        <button
          className="text"
          onClick={async () => {
            try {
              await result(
                supabase
                  .from("notifications")
                  .update({ read_at: new Date().toISOString() })
                  .eq("user_id", userId)
                  .is("read_at", null),
              );
              reload();
            } catch {
              notify("Non riesco a segnare le notifiche come lette.");
            }
          }}
        >
          Segna tutte come lette
        </button>
      )}
      {rows.map((n) => (
        <article
          className={"notification " + (!n.read_at ? "unread" : "")}
          key={n.id}
        >
          <strong>{n.title}</strong>
          <p>{n.body}</p>
          <small>{dateLabel(n.created_at)}</small>
        </article>
      ))}
    </>
  );
}

function DeleteAccount({
  email,
  enabled,
  notify,
  reload,
}: {
  email: string;
  enabled: boolean;
  notify: (s: string) => void;
  reload: () => void;
}) {
  const [code, setCode] = useState(""),
    [busy, setBusy] = useState(false),
    [confirmed, setConfirmed] = useState(false),
    [codeSent, setCodeSent] = useState(false),
    [errorMessage, setErrorMessage] = useState("");
  useEffect(() => {
    setCode("");
    setCodeSent(false);
    setErrorMessage("");
  }, [email]);
  return (
    <details className="notice">
      <summary>Elimina account</summary>
      {!enabled ? (
        <p>
          La cancellazione definitiva non è ancora attivata dal titolare, che
          deve prima definire la conservazione dei dati. Contatta
          l’amministratore.
        </p>
      ) : (
        <>
          <p>
            Il tuo account e i dati del profilo saranno eliminati. Gli
            appuntamenti futuri saranno cancellati; lo storico sarà
            anonimizzato. Questa operazione è definitiva.
          </p>
          <label className="check">
            <input
              type="checkbox"
              checked={confirmed}
              disabled={busy}
              onChange={(e) => setConfirmed(e.target.checked)}
            />
            Confermo di voler eliminare il mio account
          </label>
          <button
            className="secondary"
            disabled={busy || !confirmed}
            onClick={async () => {
              if (busy) return;
              setBusy(true);
              setErrorMessage("");
              try {
                await result(
                  supabase.auth.signInWithOtp({
                    email,
                    options: {
                      shouldCreateUser: false,
                      emailRedirectTo:
                        location.origin + import.meta.env.BASE_URL + "?delete-account=1",
                    },
                  }),
                );
                setCode("");
                setCodeSent(true);
                notify(
                  "Codice inviato via email. Inseriscilo qui per confermare l’eliminazione dell’account. Controlla anche le cartelle Spam e Posta indesiderata.",
                );
              } catch {
                setErrorMessage("Errore nell’invio, riprovare fra qualche minuto.");
              } finally {
                setBusy(false);
              }
            }}
          >
            {busy ? "Attendi…" : "Invia codice via email"}
          </button>
          {errorMessage && <p className="form-error" role="alert">{errorMessage}</p>}
          {codeSent && (
            <>
              <p className="muted">
                Abbiamo inviato il codice alla tua email. Se non lo trovi,
                controlla anche le cartelle Spam e Posta indesiderata.
              </p>
              <label>
                Codice OTP
                <input
                  value={code}
                  onChange={(e) => {
                    setCode(e.target.value.replace(/[^0-9]/g, ""));
                    setErrorMessage("");
                  }}
                  type="text"
                  name="delete-account-code"
                  autoComplete="one-time-code"
                  inputMode="numeric"
                  pattern="[0-9]+"
                  required
                  disabled={busy}
                  autoFocus
                />
              </label>
              <button
                className="danger"
                disabled={busy || !confirmed || !code.trim()}
                onClick={async () => {
                  if (busy || !confirmed || !code.trim()) return;
                  if (!confirm("Eliminare definitivamente account e profilo?")) return;
                  setBusy(true);
                  setErrorMessage("");
                  try {
                    const { error: codeError } = await supabase.auth.verifyOtp({
                      email,
                      token: code.trim(),
                      type: "email",
                    });
                    if (codeError) {
                      setErrorMessage("Errore: codice non valido o scaduto. Riprova oppure richiedi un nuovo codice.");
                      return;
                    }
                    const { error } = await supabase.functions.invoke(
                      "delete-account",
                      { body: { confirm: true } },
                    );
                    if (error) {
                      setErrorMessage(
                        "Eliminazione non riuscita. Richiedi un nuovo codice e controlla di non essere l’unico amministratore.",
                      );
                      return;
                    }
                    await supabase.auth.signOut({ scope: "local" });
                    notify("Account eliminato. Arrivederci!");
                    reload();
                  } catch {
                    setErrorMessage("Conferma non riuscita. Riprova fra qualche minuto.");
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                {busy ? "Attendi…" : "Conferma eliminazione account"}
              </button>
            </>
          )}
        </>
      )}
    </details>
  );
}
