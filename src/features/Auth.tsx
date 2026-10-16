import { useState } from "react";
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
    [busy, setBusy] = useState(false);
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
        if (!terms || !accepted) throw new Error("TERMS_REQUIRED");
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
          await result(
            supabase
              .from("terms_acceptances")
              .insert({ user_id: data.user!.id, terms_id: terms.id }),
          );
          onDone();
          close();
        } else {
          notify("Controlla la tua email e conferma la registrazione.");
          setMode("login");
        }
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email,
          password,
        });
        if (error) throw error;
        sessionStorage.setItem(
          "barbercut-password-proof",
          data.session.access_token,
        );
        onDone();
        close();
      }
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
    } finally {
      setBusy(false);
    }
  }
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
          {mode === "register" && (
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
              {!terms && (
                <p className="notice">
                  Le registrazioni apriranno dopo la pubblicazione dei termini.
                </p>
              )}
            </>
          )}
          <button
            className="primary"
            disabled={busy || (mode === "register" && !terms)}
          >
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
          sessionStorage.removeItem("barbercut-password-proof");
          done();
        }}
      >
        Esci e accedi nuovamente
      </button>
    </section>
  );
}
export async function authorizeStaff() {
  const proof = sessionStorage.getItem("barbercut-password-proof");
  if (!proof) return false;
  const { error } = await supabase.functions.invoke(
    "staff-email-verification",
    { body: { password_token: proof } },
  );
  if (error) return false;
  sessionStorage.removeItem("barbercut-password-proof");
  return true;
}
