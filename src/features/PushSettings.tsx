import ReminderSettings from "./ReminderSettings";
import { useEffect, useState } from "react";
import { Modal } from "../components/UI";
import {
  dismissPushPrompt,
  promptWasSeen,
  readPushSettings,
  pushCapability,
  syncPush,
  enablePush,
  disablePush,
} from "../lib/push";
import type { PushSettings } from "../lib/push";

function PushHelp() {
  const capability = pushCapability();
  return capability.needsHome ? (
    <p className="notice">
      Su iPhone o iPad con iOS 16.4 o successivo: apri BarberUp in Safari, tocca
      Condividi, scegli Aggiungi alla schermata Home e riapri l’app dalla sua
      icona. Poi attiva le notifiche dal Profilo.
    </p>
  ) : !capability.supported ? (
    <p className="notice">
      Le push non sono disponibili in questo browser. Usa un browser aggiornato
      e, su iPhone, apri la PWA dalla schermata Home.
    </p>
  ) : capability.permission === "denied" ? (
    <p className="notice">
      Il dispositivo ha bloccato le notifiche. Abilitale nelle impostazioni di
      BarberUp o del browser, poi torna qui.
    </p>
  ) : null;
}
export function PushSettingsPanel({ userId }: { userId: string }) {
  const [settings, setSettings] = useState<PushSettings | null>(null);
  const [active, setActive] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState("");
  useEffect(() => {
    let stopped = false;
    const load = async () => {
      try {
        const next = await readPushSettings();
        const subscribed = await syncPush(userId, next);
        if (!stopped) {
          setSettings(next);
          setActive(subscribed);
          setError("");
        }
      } catch {
        if (!stopped)
          setError(
            "Non riesco a leggere le impostazioni delle notifiche. Riprova quando sei online.",
          );
      }
    };
    void load();
    window.addEventListener("focus", load);
    window.addEventListener("barberup:push-changed", load);
    return () => {
      stopped = true;
      window.removeEventListener("focus", load);
      window.removeEventListener("barberup:push-changed", load);
    };
  }, [userId]);
  const toggle = async (checked: boolean) => {
    if (busy || !settings) return;
    setBusy(true);
    setError("");
    setMessage("");
    try {
      if (checked) {
        if (!settings.public_key)
          throw new Error(
            "Le notifiche sono in preparazione. Riprova fra qualche minuto.",
          );
        await enablePush(userId, settings.public_key);
        setActive(true);
        setSettings({ ...settings, enabled: true });
        setMessage("Promemoria push attivati su questo dispositivo.");
      } else {
        await disablePush();
        setActive(false);
        setSettings({ ...settings, enabled: false });
        setMessage("Promemoria push disattivati per il tuo account.");
      }
    } catch (e) {
      setError(
        e instanceof Error &&
          !/ACCESS_DENIED|INVALID_PUSH|PUSH_/.test(e.message)
          ? e.message
          : "Non riesco ad aggiornare le notifiche. Riprova fra qualche minuto.",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="push-settings">
      <div className="content-stack">
        <p>
          Ricevi i promemoria dei tuoi appuntamenti anche sul telefono. Le
          notifiche nel quadrifoglio restano disponibili anche se disattivi le
          push.
        </p>
        <label className="check">
          <input
            type="checkbox"
            checked={active}
            disabled={
              busy || !settings || (!pushCapability().supported && !active)
            }
            onChange={(e) => void toggle(e.target.checked)}
          />
          Promemoria push su questo dispositivo
        </label>
        {settings && !active && settings.enabled && (
          <p className="muted">
            La preferenza è attiva: completa l’attivazione su questo dispositivo
            per ricevere le push.
          </p>
        )}
        {settings && !settings.enabled && (
          <p className="muted">
            Le push sono disattivate. Puoi attivarle quando vuoi.
          </p>
        )}
        {settings?.enabled && !active && (
          <button
            type="button"
            className="text"
            disabled={busy}
            onClick={() => void toggle(false)}
          >
            Disattiva le push per il mio account
          </button>
        )}
        <ReminderSettings userId={userId} />
        <PushHelp />
        {busy && <p role="status">Aggiornamento notifiche…</p>}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        {message && (
          <p className="notice" role="status">
            {message}
          </p>
        )}
      </div>
    </div>
  );
}
export function PushOnboarding({ userId }: { userId: string }) {
  const [settings, setSettings] = useState<PushSettings | null>(null);
  const [show, setShow] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  useEffect(() => {
    let stopped = false;
    void readPushSettings()
      .then(async (next) => {
        const synced = await syncPush(userId, next);
        if (stopped) return;
        setSettings(next);
        setShow(next.enabled && !synced && !promptWasSeen(userId));
      })
      .catch(() => {});
    return () => {
      stopped = true;
    };
  }, [userId]);
  const close = () => {
    if (!busy) {
      dismissPushPrompt(userId);
      setShow(false);
    }
  };
  if (!show || !settings) return null;
  return (
    <Modal title="Ricordati del tuo appuntamento" close={close}>
      <p>
        Vuoi ricevere i promemoria dei tuoi appuntamenti anche sul telefono?
        Puoi scegliere quando riceverli da Profilo → Notifiche.
      </p>
      <PushHelp />
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <div className="two">
        <button
          type="button"
          className="secondary"
          disabled={busy}
          onClick={close}
        >
          Più tardi
        </button>
        <button
          type="button"
          className="primary"
          disabled={
            busy ||
            !settings.public_key ||
            !pushCapability().supported ||
            pushCapability().permission === "denied"
          }
          onClick={async () => {
            setBusy(true);
            setError("");
            try {
              await enablePush(userId, settings.public_key!);
              setShow(false);
            } catch (e) {
              setError(
                e instanceof Error &&
                  !/ACCESS_DENIED|INVALID_PUSH|PUSH_/.test(e.message)
                  ? e.message
                  : "Attivazione non riuscita. Riprova dal profilo fra qualche minuto.",
              );
            } finally {
              setBusy(false);
            }
          }}
        >
          {busy ? "Attivazione…" : "Attiva notifiche"}
        </button>
      </div>
    </Modal>
  );
}
