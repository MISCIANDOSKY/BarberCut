import { useCallback, useEffect, useRef, useState } from "react";
import { getPasswordProof, clearPasswordProof } from "./lib/passwordProof";
import type { User } from "@supabase/supabase-js";
import { Panel, Empty, Modal } from "./components/UI";
import PWA from "./components/PWA";
import Auth, { StaffGate, authorizeStaff } from "./features/Auth";
import Booking from "./features/Booking";
import { Appointments, Profile, Notifications } from "./features/Account";
import Manage from "./features/Manage";
import Admin from "./features/Admin";
import BarberServices from "./features/BarberServices";
import { supabase, result, euro, friendly } from "./lib/api";
import type { Row } from "./lib/api";
export default function App() {
  const [user, setUser] = useState<User | null>(null),
    [profile, setProfile] = useState<Row | null>(null),
    [role, setRole] = useState("client"),
    [verified, setVerified] = useState(false),
    [settings, setSettings] = useState<Row>({
      shop_name: "BarberCut",
      accent: "#c6a66b",
      bookings_enabled: false,
      cancellation_hours: null,
    }),
    [services, setServices] = useState<Row[]>([]),
    [barbers, setBarbers] = useState<Row[]>([]),
    [terms, setTerms] = useState<Row | null>(null),
    [accepted, setAccepted] = useState(true),
    [legal, setLegal] = useState(false),
    [appointments, setAppointments] = useState<Row[]>([]),
    [notifications, setNotifications] = useState<Row[]>([]),
    [section, setSection] = useState(""),
    [auth, setAuth] = useState(false),
    [message, setMessage] = useState(""),
    [loading, setLoading] = useState(true),
    [online, setOnline] = useState(navigator.onLine),
    [reset, setReset] = useState(false),
    [password, setPassword] = useState("");
  const refreshVersion = useRef(0);
  const notify = useCallback((s: string) => setMessage(s), []);
  const refresh = useCallback(async () => {
    const version = ++refreshVersion.current;
    try {
      const {
        data: { user: u },
      } = await supabase.auth.getUser();
      if (version !== refreshVersion.current) return;
      setUser(u);
      const [config, svcs, bs, ts] = await Promise.all([
        result(supabase.from("app_settings").select("*").single()),
        result(
          supabase
            .from("services")
            .select("*")
            .is("deleted_at", null)
            .order("price"),
        ),
        result(
          supabase
            .from("barbers")
            .select("*")
            .is("deleted_at", null)
            .order("name"),
        ),
        result(
          supabase
            .from("terms_versions")
            .select("*")
            .eq("published", true)
            .maybeSingle(),
        ),
      ]);
      if (version !== refreshVersion.current) return;
      setSettings(config as Row);
      setServices(svcs as Row[]);
      setBarbers(bs as Row[]);
      setTerms(ts as Row | null);
      document.documentElement.style.setProperty(
        "--accent",
        (config as Row).accent,
      );
      if (u) {
        const [p, r, v, ns, ap] = await Promise.all([
          result(supabase.from("profiles").select("*").eq("id", u.id).single()),
          result(
            supabase
              .from("user_roles")
              .select("role")
              .eq("user_id", u.id)
              .single(),
          ),
          result(supabase.rpc("staff_session_status")),
          result(
            supabase
              .from("notifications")
              .select("*")
              .eq("user_id", u.id)
              .order("created_at", { ascending: false })
              .limit(100),
          ),
          result(
            supabase
              .from("calendar_entries")
              .select("*")
              .eq("client_id", u.id)
              .eq("kind", "appointment")
              .eq("status", "confirmed")
              .gte("start_at", new Date().toISOString())
              .order("start_at"),
          ),
        ]);
        if (version !== refreshVersion.current) return;
        setProfile(p as Row);
        setRole((r as Row).role);
        setVerified(!!v);
        setNotifications(ns as Row[]);
        setAppointments(ap as Row[]);
        if (ts) {
          const a = await result(
            supabase
              .from("terms_acceptances")
              .select("terms_id")
              .eq("user_id", u.id)
              .eq("terms_id", (ts as Row).id)
              .maybeSingle(),
          );
          if (version === refreshVersion.current) setAccepted(!!a);
        }
      } else {
        setProfile(null);
        setRole("client");
        setVerified(false);
        setNotifications([]);
        setAppointments([]);
      }
    } catch (e) {
      if (version === refreshVersion.current) notify(friendly(e));
    } finally {
      if (version === refreshVersion.current) setLoading(false);
    }
  }, [notify]);
  useEffect(() => {
    refresh();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") setReset(true);
      if (event === "SIGNED_OUT") {
        refreshVersion.current++;
        setUser(null);
        setProfile(null);
        setRole("client");
        setVerified(false);
        setNotifications([]);
        setAppointments([]);
        setAccepted(true);
        setLoading(false);
        setSection("");
        clearPasswordProof();
      }
      if (event === "SIGNED_IN")
        setTimeout(async () => {
          if (getPasswordProof()) await authorizeStaff();
          refresh();
        }, 0);
    });
    const on = () => {
        setOnline(true);
        refresh();
      },
      off = () => setOnline(false);
    window.addEventListener("online", on);
    window.addEventListener("offline", off);
    return () => {
      refreshVersion.current++;
      subscription.unsubscribe();
      window.removeEventListener("online", on);
      window.removeEventListener("offline", off);
    };
  }, [refresh]);
  useEffect(() => {
    if (section === "Profilo") window.scrollTo({ top: 0, behavior: "instant" });
  }, [section]);
  useEffect(() => {
    if (!message) return;
    const t = setTimeout(() => setMessage(""), 9000);
    return () => clearTimeout(t);
  }, [message]);
  useEffect(() => {
    const nav = navigator as Navigator & {
      setAppBadge?: (n: number) => Promise<void>;
      clearAppBadge?: () => Promise<void>;
    };
    if (notifications.some((n) => !n.read_at))
      nav.setAppBadge?.(1).catch(() => {});
    else nav.clearAppBadge?.().catch(() => {});
  }, [notifications]);
  const staff = user && role !== "client",
    ready = staff && verified;
  const choices = ready
    ? role === "admin"
      ? [
          ["♧", "Barbieri", "Persone e agende"],
          ["◉", "Utenti", "Account e ruoli"],
          ["✂", "Servizi", "Catalogo e prezzi"],
          ["⚙", "Configurazione", "La tua attività"],
          ["▤", "Termini", "Versioni e pubblicazione"],
          ["⌘", "Manutenzione", "Dati e conservazione"],
          ["↗", "Agenda", "Apri strumenti barbiere"],
        ]
      : [
          ["▦", "Appuntamenti", "La tua agenda"],
          ["＋", "Nuova prenotazione", "Prenota per un cliente"],
          ["⊘", "Blocca orario", "Una pausa, una giornata"],
          ["◷", "Orari di lavoro", "La tua settimana"],
          ["✂", "Servizi e prezzi", "Il catalogo"],
          ["♧", "Notifiche", "Tutte le novità"],
          ["◉", "Profilo", "Il tuo account"],
        ]
    : [
        ["▦", "Prenota", "Trova il tuo prossimo momento"],
        ["✂", "Servizi e prezzi", "Scegli il tuo stile"],
        ["▤", "Le mie prenotazioni", "Tieni tutto sotto controllo"],
      ];
  const manageSections = [
    "Appuntamenti",
    "Nuova prenotazione",
    "Blocca orario",
    "Orari di lavoro",
  ];
  function content() {
    if (section === "Profilo")
      return user && profile ? (
        <Profile
          user={user}
          profile={profile}
          notify={notify}
          reload={refresh}
          deletionEnabled={!!settings.account_deletion_enabled}
        />
      ) : (
        <Empty>Accedi per visualizzare il tuo profilo.</Empty>
      );
    if (section === "Notifiche")
      return (
        <Notifications
          rows={notifications}
          reload={refresh}
          notify={notify}
          userId={user!.id}
        />
      );
    if (section === "Servizi e prezzi" && ready && role === "barber") {
      const ownBarber = barbers.find(
        (item) => item.user_id === user!.id && item.active,
      );
      return ownBarber ? (
        <BarberServices
          barberId={ownBarber.id}
          notify={notify}
          refresh={refresh}
        />
      ) : (
        <Empty>Nessuna agenda associata al tuo account.</Empty>
      );
    }
    if (section === "Servizi e prezzi")
      return services.length ? (
        <div className="service-list">
          {services.map((s) => (
            <article className="service" key={s.id}>
              <span>
                <strong>{s.name}</strong>
                <small>
                  {s.duration_minutes} minuti
                  {s.description ? " · " + s.description : ""}
                </small>
              </span>
              <strong>{euro(s.price)}</strong>
            </article>
          ))}
        </div>
      ) : (
        <Empty>
          Il catalogo è in preparazione. Torna presto per scoprire servizi e
          prezzi.
        </Empty>
      );
    if (section === "Prenota")
      return (
        <Booking
          user={user}
          settings={settings}
          services={services}
          barbers={barbers}
          notify={notify}
          login={() => setAuth(true)}
          onBooked={refresh}
        />
      );
    if (section === "Le mie prenotazioni")
      return user ? (
        <Appointments
          rows={appointments}
          settings={settings}
          reload={refresh}
          notify={notify}
        />
      ) : (
        <div className="empty">
          <p>Accedi per ritrovare i tuoi appuntamenti.</p>
          <button className="primary" onClick={() => setAuth(true)}>
            Accedi
          </button>
        </div>
      );
    if (ready && manageSections.includes(section))
      return (
        <Manage
          user={user!}
          barbers={barbers}
          services={services}
          settings={settings}
          notify={notify}
          section={section}
          isAdmin={role === "admin"}
        />
      );
    if (ready && section === "Agenda")
      return (
        <div className="mini-grid">
          {manageSections.map((s) => (
            <button className="secondary" onClick={() => setSection(s)} key={s}>
              {s}
            </button>
          ))}
        </div>
      );
    if (ready && role === "admin")
      return <Admin section={section} notify={notify} refresh={refresh} />;
    return null;
  }
  return (
    <div className="app">
      <header className="topbar">
        <button
          className="brand"
          onClick={() => setSection("")}
          aria-label="BarberCut Home"
        >
          <img src={import.meta.env.BASE_URL + "icon.svg"} alt="" />
          <span>
            Barber<span className="gold">Cut</span>
            <small>IL TUO TEMPO. IL TUO STILE.</small>
          </span>
        </button>
        <div className="top-actions">
          {user && (
            <button
              className="bell"
              onClick={() => setSection("Notifiche")}
              aria-label="Notifiche"
            >
              ♧
              {notifications.some((n) => !n.read_at) && (
                <span className="badge">1</span>
              )}
            </button>
          )}
          <button
            className="account"
            onClick={() => (user ? setSection("Profilo") : setAuth(true))}
          >
            {user ? "Profilo" : "Accedi"} <span>↗</span>
          </button>
        </div>
      </header>
      {!online && (
        <div className="offline" role="status">
          Sei offline. Collegati per visualizzare disponibilità e prenotare.
        </div>
      )}
      <main>
        {section === "Profilo" && user ? (
          <div className="workspace">
            <Panel title="Profilo" back={() => setSection("")}>
              {content()}
            </Panel>
          </div>
        ) : (
          <>
            <div className="hero">
              <div className="hero-copy">
                <span className="eyebrow">
                  <i />{" "}
                  {ready
                    ? role === "admin"
                      ? "IL TUO NEGOZIO, SOTTO CONTROLLO"
                      : "LA TUA GIORNATA IN AGENDA"
                    : "UN APPUNTAMENTO CON IL TUO STILE"}
                </span>
                <h1>
                  {profile?.first_name ? (
                    <>
                      Ciao, {profile.first_name}
                      <span className="gold">.</span>
                    </>
                  ) : (
                    <>
                      Il tuo stile.
                      <br />
                      Il tuo <em>momento.</em>
                    </>
                  )}
                </h1>
                <p>
                  {ready
                    ? "Tutto quello che serve, in un unico posto."
                    : "Un taglio fatto bene comincia dal tempo giusto. Scegli il tuo, al resto pensiamo noi."}
                </p>
                <div className="hero-rule">
                  <span>PRECISIONE</span>
                  <span>CARATTERE</span>
                  <span>CURA</span>
                </div>
              </div>
              <div className="barber-art" aria-hidden="true">
                <div className="art-circle" />
                <div className="pole">
                  <div />
                </div>
                <span className="art-word">
                  FATTO
                  <br />
                  <em>per te.</em>
                </span>
                <span className="art-caption">BARBERCUT / IL TUO STILE</span>
              </div>
            </div>
            <div className="workspace">
              <div className="section-label">
                <span>{ready ? "LA TUA AREA" : "A PORTATA DI MANO"}</span>
                <span>01 — {String(choices.length).padStart(2, "0")}</span>
              </div>
              {loading ? (
                <p className="empty" role="status">
                  Prepariamo il tuo spazio…
                </p>
              ) : staff && !verified ? (
                <StaffGate
                  email={user!.email!}
                  done={refresh}
                  notify={notify}
                />
              ) : (
                <>
                  {section && (
                    <Panel title={section} back={() => setSection("")}>
                      {content()}
                    </Panel>
                  )}
                  <nav
                    className={"main-actions " + (section ? "compact" : "")}
                    aria-label="Azioni principali"
                  >
                    {choices.map(([icon, title, sub], i) => (
                      <button
                        key={title}
                        className={
                          "action " + (title === section ? "active" : "")
                        }
                        onClick={() =>
                          setSection(section === title ? "" : title)
                        }
                        aria-expanded={section === title}
                      >
                        <span className="action-icon">{icon}</span>
                        <span className="action-copy">
                          <strong>{title}</strong>
                          <small>{sub}</small>
                        </span>
                        <span className="action-arrow">↗</span>
                        <span className="action-number">0{i + 1}</span>
                      </button>
                    ))}
                  </nav>
                </>
              )}
              {user && terms && !accepted && (
                <div className="notice">
                  <p>
                    Abbiamo aggiornato i{" "}
                    <button className="text" onClick={() => setLegal(true)}>
                      Termini e condizioni
                    </button>
                    . Leggili prima di prenotare.
                  </p>
                  <button
                    className="secondary"
                    onClick={async () => {
                      try {
                        await result(
                          supabase
                            .from("terms_acceptances")
                            .insert({ user_id: user.id, terms_id: terms.id }),
                        );
                        setAccepted(true);
                      } catch (e) {
                        notify(friendly(e));
                      }
                    }}
                  >
                    Ho letto e accetto
                  </button>
                </div>
              )}
            </div>
          </>
        )}
      </main>
      <footer>
        <div>
          <strong>{settings.shop_name}</strong>
          <span>Un piccolo gesto. Un grande stile.</span>
        </div>
        <PWA />
        <span className="footer-note">PRENOTA. ARRIVA. RINNOVA.</span>
      </footer>
      {message && (
        <div className="toast" role="status">
          <span>{message}</span>
          <button onClick={() => setMessage("")} aria-label="Chiudi messaggio">
            ×
          </button>
        </div>
      )}
      {auth && (
        <Auth
          terms={terms}
          close={() => setAuth(false)}
          notify={notify}
          onDone={refresh}
        />
      )}
      {legal && (
        <Modal title="Termini e condizioni" close={() => setLegal(false)}>
          <p className="legal">{terms?.body}</p>
        </Modal>
      )}
      {reset && (
        <Modal title="Scegli una nuova password" close={() => setReset(false)}>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              try {
                await result(supabase.auth.updateUser({ password }));
                setReset(false);
                notify("Password aggiornata.");
              } catch (e) {
                notify(friendly(e));
              }
            }}
          >
            <label>
              Nuova password
              <input
                type="password"
                minLength={8}
                autoComplete="new-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </label>
            <button className="primary">Salva password</button>
          </form>
        </Modal>
      )}
    </div>
  );
}
