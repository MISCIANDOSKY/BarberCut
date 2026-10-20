import ProfileTerms from "./ProfileTerms";
import { PushSettingsPanel } from "./PushSettings";
import { detachPushDevice } from "../lib/push";
import { confirmInApp } from "../components/AppDialogs";
import { useEffect, useRef, useState } from "react";
import { clearPasswordProof } from "../lib/passwordProof";
import { Empty, Field, Modal, TrashIcon } from "../components/UI";
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
  notify: outerNotify,
  reload,
  deletionEnabled,
  deletionFromEmail = false,
}: {
  user: Row;
  profile: Row;
  notify: (s: string) => void;
  reload: () => void;
  deletionEnabled: boolean;
  deletionFromEmail?: boolean;
}) {
  const [first, setFirst] = useState(profile.first_name),
    [last, setLast] = useState(profile.last_name),
    [phone, setPhone] = useState(profile.phone),
    [busy, setBusy] = useState(false),
    [loggingOut, setLoggingOut] = useState(false);
  const [notice, setNotice] = useState("");
  const notify = (text: string) => {
    setNotice(text);
    outerNotify(text);
  };
  const [page, setPage] = useState(deletionFromEmail ? "Elimina account" : "");
  useEffect(() => {
    if (deletionFromEmail) setPage("Elimina account");
  }, [deletionFromEmail]);
  return (
    <>
      <nav className="profile-menu" aria-label="Impostazioni del profilo">
        {[
          "Informazioni personali",
          "Termini e condizioni",
          "Notifiche",
          "Elimina account",
        ].map((label) => (
          <button
            key={label}
            type="button"
            className={
              "secondary " + (label === "Elimina account" ? "danger-text" : "")
            }
            onClick={() => {
              setNotice("");
              setPage(label);
            }}
          >
            <span>{label}</span>
            <span aria-hidden="true">→</span>
          </button>
        ))}
      </nav>
      <div>
        <button
          type="button"
          className="secondary"
          disabled={busy || loggingOut}
          style={{ width: "100%" }}
          onClick={async () => {
            if (loggingOut) return;
            setLoggingOut(true);
            try {
              await detachPushDevice();
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

      {page && (
        <Modal title={page} wide close={() => setPage("")}>
          {notice && (
            <p className="notice" role="status">
              {notice}
            </p>
          )}
          {page === "Informazioni personali" && (
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
                    setPage("");
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
              <div>
                <button
                  type="button"
                  className="secondary"
                  disabled={busy || loggingOut}
                  style={{ width: "100%" }}
                  onClick={async () => {
                    if (loggingOut) return;
                    setLoggingOut(true);
                    try {
                      await detachPushDevice();
                      const { error } = await supabase.auth.signOut({
                        scope: "local",
                      });
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
            </>
          )}
          {page === "Termini e condizioni" && (
            <ProfileTerms userId={user.id} refresh={reload} />
          )}
          {page === "Notifiche" && <PushSettingsPanel userId={user.id} />}
          {page === "Elimina account" && (
            <DeleteAccount
              fromEmailLink={deletionFromEmail}
              email={user.email}
              enabled={deletionEnabled}
              notify={notify}
              reload={reload}
            />
          )}
        </Modal>
      )}
    </>
  );
}
export function Notifications({
  rows,
  reload,
  notify,
  userId,
  onDelete,
  deleting,
}: {
  rows: Row[];
  reload: () => void;
  notify: (s: string) => void;
  userId: string;
  onDelete: (id: string) => void;
  deleting: string | null;
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
          disabled={!!deleting}
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
          <div className="notification-copy">
            <strong>{n.title}</strong>
            <p>{n.body}</p>
            <small>{dateLabel(n.created_at)}</small>
          </div>
          <button
            type="button"
            className="notification-delete"
            aria-label={"Cancella notifica: " + n.title}
            title="Cancella notifica"
            disabled={!!deleting}
            onClick={() => onDelete(n.id)}
          >
            <TrashIcon />
          </button>
        </article>
      ))}
    </>
  );
}

function DeleteAccount({
  email,
  fromEmailLink = false,
  enabled,
  notify,
  reload,
}: {
  email: string;
  fromEmailLink?: boolean;
  enabled: boolean;
  notify: (s: string) => void;
  reload: () => void;
}) {
  const [code, setCode] = useState(""),
    [busy, setBusy] = useState(false),
    [confirmed, setConfirmed] = useState(false),
    [codeSent, setCodeSent] = useState(false),
    [usingLink, setUsingLink] = useState(fromEmailLink),
    [errorMessage, setErrorMessage] = useState("");
  const detailsRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    setUsingLink(fromEmailLink);
    setConfirmed(false);
    setCode("");
    setCodeSent(false);
    setErrorMessage("");
    if (!fromEmailLink) return;
    const frame = requestAnimationFrame(() =>
      detailsRef.current?.scrollIntoView({ block: "start" }),
    );
    return () => cancelAnimationFrame(frame);
  }, [email, fromEmailLink]);
  return (
    <div ref={detailsRef} className="notice account-deletion">
      <div className="content-stack">
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
                autoFocus={fromEmailLink}
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
                          location.origin +
                          import.meta.env.BASE_URL +
                          "?delete-account=1",
                      },
                    }),
                  );
                  setCode("");
                  setCodeSent(true);
                  setUsingLink(false);
                  notify(
                    "Codice inviato via email. Inseriscilo qui per confermare l’eliminazione dell’account. Controlla anche le cartelle Spam e Posta indesiderata.",
                  );
                } catch {
                  setErrorMessage(
                    "Errore nell’invio, riprovare fra qualche minuto.",
                  );
                } finally {
                  setBusy(false);
                }
              }}
            >
              {busy ? "Attendi…" : "Invia codice via email"}
            </button>
            {errorMessage && (
              <p className="form-error" role="alert">
                {errorMessage}
              </p>
            )}
            {(codeSent || usingLink) && (
              <>
                {usingLink ? (
                  <p className="notice">
                    Hai aperto il collegamento di conferma. Per eliminare il
                    profilo, seleziona la casella di conferma e premi il
                    pulsante qui sotto. Se il collegamento è scaduto, richiedi
                    un nuovo codice via email.
                  </p>
                ) : (
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
                  </>
                )}
                <button
                  className="danger"
                  disabled={busy || !confirmed || (!usingLink && !code.trim())}
                  onClick={async () => {
                    if (busy || !confirmed || (!usingLink && !code.trim()))
                      return;
                    if (
                      !(await confirmInApp(
                        "Eliminare definitivamente account e profilo?",
                      ))
                    )
                      return;
                    setBusy(true);
                    setErrorMessage("");
                    try {
                      if (!usingLink) {
                        const { error: codeError } =
                          await supabase.auth.verifyOtp({
                            email,
                            token: code.trim(),
                            type: "email",
                          });
                        if (codeError) {
                          setErrorMessage(
                            "Errore: codice non valido o scaduto. Riprova oppure richiedi un nuovo codice.",
                          );
                          return;
                        }
                      }
                      const { error } = await supabase.functions.invoke(
                        "delete-account",
                        { body: { confirm: true } },
                      );
                      if (error) {
                        const message =
                          "Eliminazione non riuscita. Richiedi un nuovo codice; se sei l’unico amministratore, assegna prima il ruolo a un altro account.";
                        setErrorMessage(message);
                        notify(message);
                        if (usingLink) {
                          setUsingLink(false);
                          setCodeSent(false);
                        }
                        return;
                      }
                      await detachPushDevice();
                      await supabase.auth.signOut({ scope: "local" });
                      notify("Account eliminato. Arrivederci!");
                      reload();
                    } catch {
                      const message =
                        "Conferma non riuscita. Riprova fra qualche minuto.";
                      setErrorMessage(message);
                      notify(message);
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
      </div>
    </div>
  );
}
