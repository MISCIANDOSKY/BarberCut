import { useEffect, useState } from "react";
import {
  savePasswordProof,
  getPasswordProof,
  clearPasswordProof,
} from "../lib/passwordProof";
import { Field, Modal } from "../components/UI";
import { supabase, result } from "../lib/api";
import type { Row } from "../lib/api";
export default function Auth({
  close,
  notify,
  onDone,
  terms,
}: {
  close: () => void;
  notify: (s: string) => void;
  onDone: () => void;
  terms: Row | null;
}) {
  const [mode, setMode] = useState("login"),
    [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [first, setFirst] = useState(""),
    [last, setLast] = useState(""),
    [phone, setPhone] = useState(""),
    [accepted, setAccepted] = useState(false),
    [legal, setLegal] = useState(false),
    [busy, setBusy] = useState(false),
    [registrationCode, setRegistrationCode] = useState(""),
    [retrySeconds, setRetrySeconds] = useState(0);
  useEffect(() => {
    if (!retrySeconds) return;
    const timer = window.setTimeout(
      () => setRetrySeconds((n) => Math.max(0, n - 1)),
      1000,
    );
    return () => window.clearTimeout(timer);
  }, [retrySeconds]);
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      const redirect = location.origin + import.meta.env.BASE_URL;
      if (mode === "reset") {
        await result(
          supabase.auth.resetPasswordForEmail(email, { redirectTo: redirect }),
        );
        notify("Se l’email è registrata, riceverai le istruzioni.");
        close();
      } else if (mode === "register") {
        if (terms && !accepted) throw new Error("TERMS_REQUIRED");
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: redirect,
            data: { first_name: first, last_name: last, phone },
          },
        });
        if (error) throw error;
        if (data.session) {
          if (terms)
            await result(
              supabase
                .from("terms_acceptances")
                .insert({ user_id: data.user!.id, terms_id: terms.id }),
            );
          onDone();
          close();
        } else {
          notify(
            "Controlla la tua email: inserisci il codice ricevuto oppure apri il link di conferma.",
          );
          setRegistrationCode("");
          setRetrySeconds(60);
          setMode("verify");
        }
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email,
          password,
        });
        if (error) throw error;
        savePasswordProof(data.session.access_token);
        onDone();
        close();
      }
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
    } finally {
      setBusy(false);
    }
  }
  if (mode === "verify")
    return (
      <Modal title="Completa la registrazione" close={close}>
        <p>
          Inserisci il codice ricevuto via email, oppure usa il link di conferma
          presente nel messaggio.
        </p>
        <form
          onSubmit={async (event) => {
            event.preventDefault();
            if (busy) return;
            setBusy(true);
            try {
              const { error } = await supabase.auth.verifyOtp({
                email: email.trim(),
                token: registrationCode.trim(),
                type: "email",
              });
              if (error) throw error;
              notify("Email verificata! Benvenuto su BarberCut.");
              onDone();
              close();
            } catch {
              notify(
                "Il codice non è valido o è scaduto. Controllalo oppure richiedi una nuova email.",
              );
            } finally {
              setBusy(false);
            }
          }}
        >
          <Field
            label="Email di registrazione"
            name="email"
            type="email"
            value={email}
            onChange={setEmail}
          />
          <label>
            Codice di verifica
            <input
              name="registration-code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]+"
              value={registrationCode}
              onChange={(event) =>
                setRegistrationCode(event.target.value.replace(/[^0-9]/g, ""))
              }
              required
              disabled={busy}
            />
          </label>
          <button className="primary" disabled={busy}>
            {busy ? "Verifica in corso…" : "Completa registrazione"}
          </button>
        </form>
        <button
          className="text"
          disabled={busy || retrySeconds > 0 || !email.trim()}
          onClick={async () => {
            setBusy(true);
            try {
              const { error } = await supabase.auth.resend({
                type: "signup",
                email: email.trim(),
                options: {
                  emailRedirectTo: location.origin + import.meta.env.BASE_URL,
                },
              });
              if (error) throw error;
              setRetrySeconds(60);
              notify(
                "Se l’account è in attesa di conferma, riceverai una nuova email. Controlla anche la cartella spam.",
              );
            } catch {
              notify(
                "Non riesco a inviare una nuova email. Attendi un minuto e riprova.",
              );
            } finally {
              setBusy(false);
            }
          }}
        >
          {retrySeconds
            ? "Puoi richiedere una nuova email tra " + retrySeconds + " secondi"
            : "Invia di nuovo l’email"}
        </button>
        <button
          className="text"
          disabled={busy}
          onClick={() => setMode("login")}
        >
          Torna ad Accedi
        </button>
      </Modal>
    );
  return (
    <>
      <Modal
        title={
          mode === "register"
            ? "Crea il tuo account"
            : mode === "reset"
              ? "Recupera password"
              : "Bentornato"
        }
        close={close}
      >
        <p className="muted">Il tuo prossimo appuntamento comincia qui.</p>
        <form onSubmit={submit}>
          {mode === "register" && (
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
          )}
          <Field
            label="Email"
            name="email"
            type="email"
            value={email}
            onChange={setEmail}
          />
          {mode === "register" && (
            <Field
              label="Telefono"
              name="tel"
              type="tel"
              value={phone}
              onChange={setPhone}
            />
          )}
          {mode !== "reset" && (
            <label>
              Password
              <input
                type="password"
                autoComplete={
                  mode === "register" ? "new-password" : "current-password"
                }
                minLength={8}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </label>
          )}
          {mode === "register" && terms && (
            <>
              <label className="check">
                <input
                  type="checkbox"
                  required
                  checked={accepted}
                  onChange={(e) => setAccepted(e.target.checked)}
                />
                Accetto i{" "}
                <button
                  className="text"
                  type="button"
                  onClick={() => setLegal(true)}
                >
                  Termini e condizioni
                </button>
              </label>
            </>
          )}
          <button className="primary" disabled={busy}>
            {busy
              ? "Attendi…"
              : mode === "register"
                ? "Registrati"
                : mode === "reset"
                  ? "Invia email"
                  : "Accedi"}
          </button>
        </form>
        <div className="auth-links">
          <button className="text" onClick={() => setMode("verify")}>
            Hai già un codice? Conferma la tua email
          </button>
          <button
            className="text"
            onClick={() => setMode(mode === "register" ? "login" : "register")}
          >
            {mode === "register"
              ? "Hai già un account? Accedi"
              : "Non hai un account? Registrati"}
          </button>
          <button
            className="text"
            onClick={() => setMode(mode === "reset" ? "login" : "reset")}
          >
            {mode === "reset" ? "Torna ad Accedi" : "Password dimenticata?"}
          </button>
        </div>
      </Modal>
      {legal && (
        <Modal title="Termini e condizioni" close={() => setLegal(false)}>
          <p className="legal">
            {terms?.body || "Termini non ancora pubblicati."}
          </p>
        </Modal>
      )}
    </>
  );
}
export function StaffGate({
  email,
  done,
  notify,
}: {
  email: string;
  done: () => void;
  notify: (s: string) => void;
}) {
  const [code, setCode] = useState(""),
    [busy, setBusy] = useState(false),
    [sent, setSent] = useState(false);
  async function send() {
    setBusy(true);
    try {
      await result(
        supabase.auth.signInWithOtp({
          email,
          options: {
            shouldCreateUser: false,
            emailRedirectTo: location.origin + import.meta.env.BASE_URL,
          },
        }),
      );
      setSent(true);
      notify(
        "Email inviata. Inserisci il codice oppure apri il link nello stesso browser.",
      );
    } catch {
      notify(
        "Invio non riuscito. Controlla la configurazione email di Supabase e riprova.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function verify(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await result(
        supabase.auth.verifyOtp({ email, token: code, type: "email" }),
      );
      done();
    } catch {
      notify(
        "Codice non valido o scaduto. Accedi nuovamente con la password e riprova.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="panel">
      <span className="eyebrow">ACCESSO RISERVATO</span>
      <h2>Un ultimo passaggio.</h2>
      <p>Per proteggere l’agenda, conferma l’accesso tramite la tua email.</p>
      <button className="primary" onClick={send} disabled={busy}>
        {busy ? "Attendi…" : sent ? "Invia di nuovo" : "Invia verifica email"}
      </button>
      {sent && (
        <form onSubmit={verify}>
          <label>
            Codice ricevuto via email
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              required
            />
          </label>
          <button className="secondary" disabled={busy}>
            Verifica codice
          </button>
          <p className="muted">
            Se l’email contiene un link, aprilo nello stesso browser. Il codice
            richiede il modello email OTP configurato in Supabase.
          </p>
        </form>
      )}
      <button
        className="text"
        onClick={async () => {
          await supabase.auth.signOut();
          clearPasswordProof();
          done();
        }}
      >
        Esci e accedi nuovamente
      </button>
    </section>
  );
}
export async function authorizeStaff() {
  const proof = getPasswordProof();
  if (!proof) return false;
  const { error } = await supabase.functions.invoke(
    "staff-email-verification",
    { body: { password_token: proof } },
  );
  if (error) return false;
  clearPasswordProof();
  return true;
}
