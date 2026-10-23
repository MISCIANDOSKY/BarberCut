import PasswordRecovery from "./PasswordRecovery";
import { sendExistingAccountCode, loginCodeError } from "../lib/loginCode.mjs";
import { useEffect, useId, useState } from "react";
import {
  savePasswordProof,
  getPasswordProof,
  clearPasswordProof,
} from "../lib/passwordProof";
import { Field, Modal } from "../components/UI";
import { supabase, result } from "../lib/api";
import type { Row } from "../lib/api";
const SEND_ERROR = "Errore nell’invio, riprovare fra qualche minuto.";
const CODE_ERROR =
  "Errore: codice non valido o scaduto. Riprova oppure richiedi un nuovo codice.";

export default function Auth({
  close,
  notify,
  onDone,
  onRecovery,
  terms,
  requiresApproval = true,
}: {
  close: () => void;
  notify: (s: string) => void;
  onDone: () => void;
  onRecovery: () => void;
  terms: Row | null;
  requiresApproval?: boolean;
}) {
  const [mode, setMode] = useState("login"),
    [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [first, setFirst] = useState(""),
    [last, setLast] = useState(""),
    [phone, setPhone] = useState(""),
    [phonePrefix, setPhonePrefix] = useState("+39"),
    [accepted, setAccepted] = useState(false),
    [legal, setLegal] = useState(false),
    [busy, setBusy] = useState(false),
    [registrationCode, setRegistrationCode] = useState(""),
    [retrySeconds, setRetrySeconds] = useState(0),
    [errorMessage, setErrorMessage] = useState(""),
    [codeError, setCodeError] = useState("");
  const codeErrorId = useId();
  useEffect(() => {
    setErrorMessage("");
    setCodeError("");
  }, [mode, email]);
  useEffect(() => {
    if (!retrySeconds) return;
    const timer = window.setTimeout(
      () => setRetrySeconds((n) => Math.max(0, n - 1)),
      1000,
    );
    return () => window.clearTimeout(timer);
  }, [retrySeconds]);
  async function sendLoginCode() {
    if (busy || retrySeconds > 0) return;
    if (mode !== "otpVerify") setMode("otp");
    setBusy(true);
    setErrorMessage("");
    setCodeError("");
    try {
      clearPasswordProof();
      await sendExistingAccountCode(
        supabase.auth,
        email,
        location.origin + import.meta.env.BASE_URL,
      );
      setRegistrationCode("");
      setRetrySeconds(60);
      setMode("otpVerify");
      notify(
        "Se l’email è associata a un account, riceverai il codice di accesso. Controlla anche le cartelle Spam e Posta indesiderata.",
      );
    } catch (error) {
      setErrorMessage(loginCodeError(error));
    } finally {
      setBusy(false);
    }
  }
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (mode === "otp") {
      await sendLoginCode();
      return;
    }
    setBusy(true);
    setErrorMessage("");
    try {
      const redirect = location.origin + import.meta.env.BASE_URL;
      if (mode === "register") {
        if (
          !/^\+[1-9][0-9]{0,2}$/.test(phonePrefix) ||
          !/^[0-9]{10}$/.test(phone)
        ) {
          setErrorMessage(
            "Controlla il prefisso e inserisci un numero di telefono composto da 10 cifre.",
          );
          return;
        }
        if (terms && !accepted) throw new Error("TERMS_REQUIRED");
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: redirect,
            data: {
              first_name: first,
              last_name: last,
              phone: phonePrefix + phone,
              phone_country_code: phonePrefix,
              phone_national: phone,
            },
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
            "Controlla la tua email: inserisci il codice ricevuto oppure apri il link di conferma. Controlla anche le cartelle Spam e Posta indesiderata.",
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
      const message = e instanceof Error ? e.message : String(e);
      setErrorMessage(
        mode === "reset" ||
          (mode === "register" &&
            /email.*(send|rate)|smtp|sending|rate.*email/i.test(message))
          ? SEND_ERROR
          : (await import("../lib/api")).friendly(e),
      );
    } finally {
      setBusy(false);
    }
  }
  if (mode === "reset")
    return (
      <PasswordRecovery
        initialEmail={email}
        close={() => setMode("login")}
        verified={() => {
          clearPasswordProof();
          onRecovery();
          onDone();
          close();
        }}
      />
    );
  const verifyingLogin = mode === "otpVerify";
  if (mode === "verify" || verifyingLogin)
    return (
      <Modal
        title={
          verifyingLogin
            ? "Accedi con codice di verifica"
            : "Completa la registrazione"
        }
        close={close}
      >
        <p>
          Inserisci il codice ricevuto via email, oppure usa il link di conferma
          presente nel messaggio. Se non trovi l’email, controlla anche le
          cartelle Spam e Posta indesiderata.
        </p>
        {errorMessage && (
          <p className="form-error" role="alert">
            {errorMessage}
          </p>
        )}
        <form
          onSubmit={async (event) => {
            event.preventDefault();
            if (busy) return;
            setBusy(true);
            setCodeError("");
            setErrorMessage("");
            try {
              const { error } = await supabase.auth.verifyOtp({
                email: email.trim(),
                token: registrationCode.trim(),
                type: "email",
              });
              if (error) throw error;
              if (verifyingLogin) await authorizeStaff();
              notify(
                verifyingLogin
                  ? "Accesso effettuato. Bentornato!"
                  : "Email verificata. Puoi consultare lo stato della tua iscrizione nell’app.",
              );
              onDone();
              close();
            } catch {
              setCodeError(CODE_ERROR);
            } finally {
              setBusy(false);
            }
          }}
        >
          <Field
            label={
              verifyingLogin ? "Email di accesso" : "Email di registrazione"
            }
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
              aria-invalid={!!codeError}
              aria-describedby={codeError ? codeErrorId : undefined}
              onChange={(event) => {
                setRegistrationCode(event.target.value.replace(/[^0-9]/g, ""));
                setCodeError("");
              }}
              required
              disabled={busy}
            />
          </label>
          {codeError && (
            <p id={codeErrorId} className="form-error" role="alert">
              {codeError}
            </p>
          )}
          <button className="primary" disabled={busy}>
            {busy
              ? "Verifica in corso…"
              : verifyingLogin
                ? "Accedi"
                : "Completa registrazione"}
          </button>
        </form>
        <button
          className="text"
          disabled={busy || retrySeconds > 0 || !email.trim()}
          onClick={async () => {
            if (verifyingLogin) {
              await sendLoginCode();
              return;
            }
            setBusy(true);
            setErrorMessage("");
            setCodeError("");
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
                "Se l’account è in attesa di conferma, riceverai una nuova email. Controlla anche le cartelle Spam e Posta indesiderata.",
              );
            } catch {
              setErrorMessage(SEND_ERROR);
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
              : mode === "otp"
                ? "Accedi con codice di verifica"
                : "Bentornato"
        }
        close={close}
      >
        <p className="muted">
          {mode === "otp"
            ? "Inserisci l’email del tuo account: ti invieremo un codice per accedere senza password. Se non trovi l’email, controlla anche le cartelle Spam e Posta indesiderata."
            : "Il tuo prossimo appuntamento comincia qui."}
        </p>
        {errorMessage && (
          <p className="form-error" role="alert">
            {errorMessage}
          </p>
        )}
        {mode === "register" && requiresApproval && (
          <p className="notice">
            Dopo aver verificato l’email, la tua iscrizione dovrà essere
            approvata dall’admin o da un barbiere. Riceverai un’email quando
            potrai prenotare.
          </p>
        )}
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
            <div className="registration-phone">
              <label>
                Prefisso
                <input
                  type="tel"
                  name="tel-country-code"
                  inputMode="tel"
                  autoComplete="tel-country-code"
                  value={phonePrefix}
                  maxLength={4}
                  pattern="\+[1-9][0-9]{0,2}"
                  required
                  data-app-control="true"
                  aria-label="Prefisso internazionale"
                  onChange={(event) => {
                    const prefix =
                      "+" + event.target.value.replace(/[^0-9]/g, "");
                    event.currentTarget.setCustomValidity(
                      /^\+[1-9][0-9]{0,2}$/.test(prefix)
                        ? ""
                        : "Inserisci un prefisso valido, per esempio +39.",
                    );
                    setPhonePrefix(prefix);
                  }}
                />
              </label>
              <label>
                Numero di telefono
                <input
                  name="tel"
                  type="tel"
                  inputMode="numeric"
                  autoComplete="tel-national"
                  pattern="[0-9]{10}"
                  minLength={10}
                  required
                  value={phone}
                  aria-describedby="registration-phone-help"
                  aria-invalid={!!phone && !/^[0-9]{10}$/.test(phone)}
                  data-app-control="true"
                  onChange={(event) => {
                    const digits = event.target.value.replace(/[^0-9]/g, "");
                    event.currentTarget.setCustomValidity(
                      /^[0-9]{10}$/.test(digits)
                        ? ""
                        : "Inserisci un numero di telefono composto da 10 cifre.",
                    );
                    setPhone(digits);
                  }}
                />
                <small id="registration-phone-help">
                  Inserisci 10 cifre, senza prefisso internazionale.
                </small>
                {phone && !/^[0-9]{10}$/.test(phone) && (
                  <span className="danger-text">
                    Il numero deve contenere esattamente 10 cifre.
                  </span>
                )}
              </label>
            </div>
          )}
          {(mode === "login" || mode === "register") && (
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
                <span style={{ flex: "1 1 220px" }}>
                  Dichiaro di aver letto e accettato i{" "}
                  <button
                    className="text"
                    type="button"
                    onClick={() => setLegal(true)}
                  >
                    termini e condizioni di utilizzo
                  </button>{" "}
                  e di aver preso visione dell'informativa sul trattamento dei
                  dati personali (privacy policy)
                </span>
              </label>
            </>
          )}
          <button
            className="primary"
            disabled={busy || (mode === "otp" && retrySeconds > 0)}
          >
            {mode === "otp" && retrySeconds > 0
              ? "Riprova tra " + retrySeconds + " secondi"
              : busy
                ? "Attendi…"
                : mode === "register"
                  ? "Registrati"
                  : mode === "reset"
                    ? "Invia email"
                    : mode === "otp"
                      ? "Invia codice di accesso"
                      : "Accedi"}
          </button>
        </form>
        <div className="auth-links">
          <button
            className="text"
            disabled={busy}
            onClick={() => {
              if (mode === "otp") setMode("login");
              else if (
                /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) &&
                retrySeconds === 0
              )
                void sendLoginCode();
              else if (email.trim() && retrySeconds > 0) setMode("otpVerify");
              else setMode("otp");
            }}
          >
            {mode === "otp"
              ? "Accedi con password"
              : "Accedi con codice di verifica"}
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
    [sent, setSent] = useState(false),
    [sendError, setSendError] = useState(""),
    [codeError, setCodeError] = useState("");
  const codeErrorId = useId();
  async function send() {
    if (busy) return;
    setBusy(true);
    setSendError("");
    setCodeError("");
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
        "Email inviata. Inserisci il codice oppure apri il link nello stesso browser. Controlla anche le cartelle Spam e Posta indesiderata.",
      );
    } catch {
      setSendError(SEND_ERROR);
    } finally {
      setBusy(false);
    }
  }
  async function verify(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setCodeError("");
    setSendError("");
    try {
      await result(
        supabase.auth.verifyOtp({ email, token: code.trim(), type: "email" }),
      );
      done();
    } catch {
      setCodeError(CODE_ERROR);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="panel content-stack">
      <span className="eyebrow">ACCESSO RISERVATO</span>
      <h2>Un ultimo passaggio.</h2>
      <p>
        Per proteggere l’agenda, conferma l’accesso tramite la tua email. Se non
        trovi l’email, controlla anche le cartelle Spam e Posta indesiderata.
      </p>
      <button className="primary" onClick={send} disabled={busy}>
        {busy ? "Attendi…" : sent ? "Invia di nuovo" : "Invia verifica email"}
      </button>
      {sendError && (
        <p className="form-error" role="alert">
          {sendError}
        </p>
      )}
      {sent && (
        <form onSubmit={verify}>
          <label>
            Codice ricevuto via email
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              value={code}
              aria-invalid={!!codeError}
              aria-describedby={codeError ? codeErrorId : undefined}
              onChange={(e) => {
                setCode(e.target.value.replace(/[^0-9]/g, ""));
                setCodeError("");
              }}
              required
            />
          </label>
          {codeError && (
            <p id={codeErrorId} className="form-error" role="alert">
              {codeError}
            </p>
          )}
          <button className="secondary" disabled={busy}>
            Verifica codice
          </button>
          <p className="muted">
            Inserisci il codice scritto nell’email. Se preferisci usare il link,
            aprilo nello stesso browser. Se non trovi l’email, controlla anche
            le cartelle Spam e Posta indesiderata.
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
  const { error } = await supabase.functions.invoke(
    "staff-email-verification",
    { body: proof ? { password_token: proof } : {} },
  );
  if (error) return false;
  clearPasswordProof();
  return true;
}
