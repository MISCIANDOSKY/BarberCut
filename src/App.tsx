import AppointmentLog from "./features/AppointmentLog";
import TermsGate from "./features/TermsGate";
import { useTermsConsent } from "./lib/useTermsConsent";
import { ResetPasswordDialog } from "./features/PasswordRecovery";
import BookingHorizon from "./features/BookingHorizon";
import { PushOnboarding } from "./features/PushSettings";
import { detachPushDevice } from "./lib/push";
import { confirmInApp } from "./components/AppDialogs";
import { useCallback, useEffect, useRef, useState } from "react";
import { createLatestRequest } from "./lib/latestRequest.mjs";
import { clearPasswordProof } from "./lib/passwordProof";
import type { User } from "@supabase/supabase-js";
import { Empty, Modal, TrashIcon } from "./components/UI";
import PWA from "./components/PWA";
import ShopAgenda from "./features/ShopAgenda";
import Auth, { StaffGate, authorizeStaff } from "./features/Auth";
import Booking from "./features/Booking";
import { Appointments, Profile, Notifications } from "./features/Account";
import Manage from "./features/Manage";
import Admin from "./features/Admin";
import BarberServices from "./features/BarberServices";
import HireBarber from "./features/HireBarber";
import ServiceCatalog from "./features/ServiceCatalog";
import Information from "./features/Information";
import ManageUsers from "./features/ManageUsers";
import BarberAddress from "./features/BarberAddress";
import RegistrationPolicy from "./features/RegistrationPolicy";
import RecurringPolicy from "./features/RecurringPolicy";
import { supabase, result, friendly } from "./lib/api";
import type { Row } from "./lib/api";
export default function App() {
  const [user, setUser] = useState<User | null>(null),
    [profile, setProfile] = useState<Row | null>(null),
    [role, setRole] = useState("client"),
    [membership, setMembership] = useState("approved"),
    [verified, setVerified] = useState(false),
    [reviewAllowed, setReviewAllowed] = useState(false),
    [logAllowed, setLogAllowed] = useState(false),
    [settings, setSettings] = useState<Row>({
      shop_name: "BarberUp",
      accent: "#c6a66b",
      bookings_enabled: false,
      cancellation_hours: null,
    }),
    [services, setServices] = useState<Row[]>([]),
    [barbers, setBarbers] = useState<Row[]>([]),
    [terms, setTerms] = useState<Row | null>(null),
    [legal, setLegal] = useState(false),
    [appointments, setAppointments] = useState<Row[]>([]),
    [notifications, setNotifications] = useState<Row[]>([]),
    [agendaContext, setAgendaContext] = useState<{
      barberId: string;
      day: string;
    } | null>(null),
    [deletionFromEmail, setDeletionFromEmail] = useState(
      () => new URLSearchParams(location.search).get("delete-account") === "1",
    ),
    [section, setSection] = useState(() =>
      new URLSearchParams(location.search).get("delete-account") === "1"
        ? "Profilo"
        : new URLSearchParams(location.search).get("book") === "1"
          ? "Prenota"
          : new URLSearchParams(location.search).get("appointments") === "1"
            ? "Le mie prenotazioni"
            : "",
    ),
    [auth, setAuth] = useState(
      () => new URLSearchParams(location.search).get("keep-active") === "1",
    ),
    [message, setMessage] = useState(""),
    [loading, setLoading] = useState(true),
    [online, setOnline] = useState(navigator.onLine),
    [reset, setReset] = useState(false),
    [deletingNotification, setDeletingNotification] = useState<string | null>(
      null,
    );
  function dismissDeletionLink() {
    setDeletionFromEmail(false);
    const address = new URL(location.href);
    if (address.searchParams.has("delete-account")) {
      address.searchParams.delete("delete-account");
      history.replaceState(
        history.state,
        "",
        address.pathname + address.search + address.hash,
      );
    }
  }
  const refreshVersion = useRef(0);
  const notificationRevision = useRef(0);
  const notificationDeleteInFlight = useRef(false);
  const notificationAccount = useRef<string | null>(null);
  notificationAccount.current = user?.id ?? null;
  const keepActiveRequested = useRef(
    new URLSearchParams(location.search).get("keep-active") === "1",
  );
  const consent = useTermsConsent(user?.id ?? null);
  const notify = useCallback((s: string) => setMessage(s), []);
  const refresh = useCallback(async () => {
    const version = ++refreshVersion.current;
    const notificationReadRevision = notificationRevision.current;
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
        // Keep a server timestamp even when an existing login session is reused.
        const { error: activityError } = await supabase.rpc("record_activity");
        if (!activityError && keepActiveRequested.current) {
          keepActiveRequested.current = false;
          setAuth(false);
          const address = new URL(location.href);
          address.searchParams.delete("keep-active");
          history.replaceState(
            history.state,
            "",
            address.pathname + address.search + address.hash,
          );
          notify(
            "Il tuo account è attivo. Il conteggio dell’inattività è ripartito da oggi.",
          );
        }
        const [p, r, v, ns, ap, member, reviewPermission, logPermission] =
          await Promise.all([
            result(
              supabase.from("profiles").select("*").eq("id", u.id).single(),
            ),
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
                .is("dismissed_at", null)
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
            result(supabase.rpc("membership_status")),
            result(supabase.rpc("can_review_registrations")),
            result(supabase.rpc("can_view_appointment_log")),
          ]);
        if (version !== refreshVersion.current) return;
        setMembership(String(member));
        setProfile(p as Row);
        setRole((r as Row).role);
        setVerified(!!v);
        setReviewAllowed(reviewPermission === true);
        setLogAllowed(logPermission === true);
        if (notificationReadRevision === notificationRevision.current)
          setNotifications(ns as Row[]);
        setAppointments(ap as Row[]);
      } else {
        setProfile(null);
        setRole("client");
        setMembership("approved");
        setVerified(false);
        setReviewAllowed(false);
        setLogAllowed(false);
        setNotifications([]);
        setDeletingNotification(null);
        notificationRevision.current++;
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
        dismissDeletionLink();
        refreshVersion.current++;
        setUser(null);
        setProfile(null);
        setRole("client");
        setMembership("approved");
        setVerified(false);
        setReviewAllowed(false);
        setLogAllowed(false);
        setNotifications([]);
        setDeletingNotification(null);
        notificationRevision.current++;
        setAppointments([]);
        setLoading(false);
        setSection("");
        clearPasswordProof();
      }
      if (event === "SIGNED_IN")
        setTimeout(async () => {
          await authorizeStaff();
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
    if (!user) return;
    const record = () => {
      if (document.visibilityState === "visible") {
        void supabase.rpc("record_activity").then(() => {});
      }
    };
    const timer = window.setInterval(record, 15 * 60 * 1000);
    window.addEventListener("focus", record);
    document.addEventListener("visibilitychange", record);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", record);
      document.removeEventListener("visibilitychange", record);
    };
  }, [user?.id]);
  useEffect(() => {
    if (!user || role === "client" || !verified) return;
    let stopped = false;
    let request = 0;
    const check = async () => {
      if (document.hidden) return;
      const version = ++request;
      const [review, log] = await Promise.all([
        supabase.rpc("can_review_registrations"),
        supabase.rpc("can_view_appointment_log"),
      ]);
      if (!stopped && version === request) {
        setReviewAllowed(!review.error && review.data === true);
        setLogAllowed(!log.error && log.data === true);
      }
    };
    void check();
    const timer = window.setInterval(check, 30000);
    window.addEventListener("focus", check);
    document.addEventListener("visibilitychange", check);
    return () => {
      stopped = true;
      window.clearInterval(timer);
      window.removeEventListener("focus", check);
      document.removeEventListener("visibilitychange", check);
    };
  }, [user?.id, role, verified]);
  useEffect(() => {
    if (!user || role !== "client" || membership !== "pending") return;
    const check = async () => {
      if (document.visibilityState !== "visible" || !navigator.onLine) return;
      const { data, error } = await supabase.rpc("membership_status");
      if (!error && data) setMembership(String(data));
    };
    const timer = window.setInterval(check, 60000);
    window.addEventListener("focus", check);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", check);
    };
  }, [user?.id, role, membership]);
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
  useEffect(() => {
    if (!user || section !== "Le mie prenotazioni") return;
    const request = createLatestRequest<Row[]>({
      load: () =>
        result(
          supabase
            .from("calendar_entries")
            .select("*")
            .eq("client_id", user.id)
            .eq("kind", "appointment")
            .eq("status", "confirmed")
            .gte("start_at", new Date().toISOString())
            .order("start_at"),
        ),
      onData: setAppointments,
      onError: () =>
        notify("Non riesco ad aggiornare le prenotazioni. Riprova."),
    });
    const update = () => {
      if (!document.hidden && navigator.onLine) void request.refresh();
    };
    update();
    const timer = window.setInterval(update, 30000);
    window.addEventListener("focus", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      request.stop();
      window.clearInterval(timer);
      window.removeEventListener("focus", update);
      document.removeEventListener("visibilitychange", update);
    };
  }, [section, user?.id, notify]);
  useEffect(() => {
    if (!user) return;
    const request = createLatestRequest<{ rows: Row[]; revision: number }>({
      load: async () => {
        const revision = notificationRevision.current;
        const rows = await result<Row[]>(
          supabase
            .from("notifications")
            .select("*")
            .eq("user_id", user.id)
            .is("dismissed_at", null)
            .order("created_at", { ascending: false })
            .limit(100),
        );
        return { rows, revision };
      },
      onData: ({ rows, revision }) => {
        if (
          !notificationDeleteInFlight.current &&
          revision === notificationRevision.current
        )
          setNotifications(rows);
      },
      // Keep existing notifications when temporarily offline; retry on focus/online.
      onError: () => {},
    });
    const update = () => {
      if (!document.hidden && navigator.onLine) void request.refresh();
    };
    update();
    const timer = window.setInterval(update, 30000);
    window.addEventListener("focus", update);
    window.addEventListener("online", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      request.stop();
      window.clearInterval(timer);
      window.removeEventListener("focus", update);
      window.removeEventListener("online", update);
      document.removeEventListener("visibilitychange", update);
    };
  }, [user?.id]);
  async function removeNotification(id?: string) {
    const owner = user?.id;
    if (!owner || notificationDeleteInFlight.current) return;
    if (!id && !(await confirmInApp("Vuoi cancellare tutte le tue notifiche?")))
      return;
    if (notificationAccount.current !== owner) return;
    notificationDeleteInFlight.current = true;
    notificationRevision.current++;
    setDeletingNotification(id || "all");
    try {
      await result(supabase.rpc("dismiss_notifications", { p_id: id || null }));
      if (notificationAccount.current !== owner) return;
      notificationRevision.current++;
      setNotifications((current) =>
        id ? current.filter((item) => item.id !== id) : [],
      );
      notify(
        id
          ? "Notifica cancellata."
          : "Tutte le notifiche sono state cancellate.",
      );
      await refresh();
    } catch (error) {
      if (notificationAccount.current === owner) notify(friendly(error));
    } finally {
      notificationRevision.current++;
      notificationDeleteInFlight.current = false;
      if (notificationAccount.current === owner) setDeletingNotification(null);
    }
  }
  const staff = user && role !== "client",
    ready = staff && verified,
    canReview = ready && (role === "admin" || reviewAllowed),
    canConfigureShop =
      ready &&
      (role === "admin" ||
        (role === "barber_admin" &&
          barbers.some(
            (barber) =>
              barber.user_id === user!.id &&
              barber.active &&
              !barber.deleted_at,
          )));
  const clientChoices = [
    ["▦", "Prenota", "Trova il tuo prossimo momento"],
    ["✂", "Servizi e prezzi", "Scegli il tuo stile"],
    ["▤", "Le mie prenotazioni", "Tieni tutto sotto controllo"],
    ["ⓘ", "Informazioni", "Indirizzo e orari della barberia"],
  ];
  const choices = ready
    ? role === "admin"
      ? [
          ["♧", "Barbieri", "Persone e agende"],
          ["◉", "Utenti", "Account e ruoli"],
          ["✓", "Gestisci utenti", "Approva le nuove iscrizioni"],
          ["✂", "Servizi", "Catalogo e prezzi"],
          ["⚙", "Configurazione", "La tua attività"],
          ["▤", "Termini", "Versioni e pubblicazione"],
          ["⌘", "Manutenzione", "Dati e conservazione"],
          ["↗", "Agenda", "Apri strumenti barbiere"],
          ["◉", "Cliente", "Prenota un appuntamento per te"],
          ...(logAllowed ? [["▤", "Log", "Operazioni sulle agende"]] : []),
        ]
      : [
          ["▦", "Appuntamenti", "La tua agenda"],
          ["＋", "Nuova prenotazione", "Prenota per un cliente"],
          ["⊘", "Blocca orario", "Una pausa, una giornata"],
          ["◷", "Orari di lavoro", "La tua settimana"],
          ["✂", "Servizi e prezzi", "Il catalogo"],
          ...(role === "barber_admin"
            ? [["⚙", "Configurazione", "Impostazioni della barberia"]]
            : []),
          ...(canReview ? [["✓", "Utenti", "Clienti della barberia"]] : []),
          ["♧", "Notifiche", "Tutte le novità"],
          ...(role === "barber_admin" && canConfigureShop
            ? [["＋", "Assumi Barbiere", "Aggiungi un collaboratore"]]
            : []),
          ...(role !== "barber_admin"
            ? [["⚙", "Configurazione", "Impostazioni della barberia"]]
            : []),
          ...(logAllowed ? [["▤", "Log", "Operazioni sulle agende"]] : []),
        ]
    : user
      ? clientChoices
      : clientChoices.filter(
          ([, title]) =>
            title === "Servizi e prezzi" || title === "Informazioni",
        );
  const manageSections = [
    "Appuntamenti",
    "Nuova prenotazione",
    "Blocca orario",
    "Orari di lavoro",
  ];
  function content() {
    if (!user && (section === "Prenota" || section === "Le mie prenotazioni"))
      return (
        <div className="content-stack">
          <p>
            Accedi o crea un account per prenotare e visualizzare i tuoi
            appuntamenti.
          </p>
          <button
            type="button"
            className="primary"
            onClick={() => setAuth(true)}
          >
            Accedi o registrati
          </button>
        </div>
      );
    if (section === "Log")
      return ready && logAllowed ? (
        <AppointmentLog key={user!.id} />
      ) : (
        <Empty>Non hai accesso ai log.</Empty>
      );
    if (section === "Cliente" && ready && role === "admin")
      return (
        <nav className="mini-grid" aria-label="Funzioni cliente">
          {clientChoices.map(([icon, title]) => (
            <button
              className="secondary"
              key={title}
              onClick={() => setSection(title)}
            >
              {icon} {title}
            </button>
          ))}
        </nav>
      );
    if (
      section === "Gestisci utenti" ||
      (section === "Utenti" && role !== "admin")
    )
      return canReview ? (
        <ManageUsers isAdmin={role === "admin"} />
      ) : (
        <Empty>
          Non sei abilitato ad approvare i nuovi utenti. Rivolgiti al tuo
          titolare.
        </Empty>
      );
    if (section === "Informazioni") return <Information />;
    if (
      section === "Assumi Barbiere" &&
      ready &&
      role === "barber_admin" &&
      canConfigureShop
    )
      return <HireBarber refresh={refresh} notify={notify} />;
    if (
      section === "Configurazione" &&
      ready &&
      (role === "barber" || role === "barber_admin")
    )
      return canConfigureShop ? (
        <>
          <BarberAddress
            address={settings.shop_address || ""}
            revision={settings.address_revision || 0}
            refresh={refresh}
          />
          <BookingHorizon settings={settings} refresh={refresh} />
          <RecurringPolicy settings={settings} refresh={refresh} />
          <RegistrationPolicy
            required={settings.require_user_approval !== false}
            refresh={refresh}
          />
        </>
      ) : (
        <div className="content-stack">
          <p className="muted">
            Queste impostazioni sono gestite dal tuo titolare.
          </p>
          <section className="content-stack">
            <h3>Indirizzo della barberia</h3>
            <p>{settings.shop_address || "Indirizzo non ancora inserito."}</p>
          </section>
          <section className="content-stack">
            <h3>Prenotazioni periodiche</h3>
            <p>
              {settings.recurring_unlimited
                ? "Nessun limite al numero di appuntamenti periodici futuri."
                : "Massimo " +
                  (settings.recurring_max ?? 5) +
                  " appuntamenti periodici futuri per cliente."}
            </p>
          </section>
          <section className="content-stack">
            <h3>Iscrizione nuovi clienti</h3>
            <p>
              {settings.require_user_approval !== false
                ? "I nuovi clienti devono essere approvati."
                : "I nuovi clienti sono accettati senza approvazione."}
            </p>
          </section>
        </div>
      );
    if (section === "Profilo")
      return user && profile ? (
        <Profile
          user={user}
          profile={profile}
          notify={notify}
          reload={refresh}
          onRecovery={() => setReset(true)}
          deletionEnabled={!!settings.account_deletion_enabled}
          deletionFromEmail={deletionFromEmail}
        />
      ) : (
        <div className="content-stack">
          <p>
            {deletionFromEmail
              ? "Apri il collegamento ricevuto via email per confermare l’eliminazione, oppure accedi e richiedi un nuovo codice dal profilo."
              : "Accedi per visualizzare il tuo profilo."}
          </p>
          <button className="secondary" onClick={() => setAuth(true)}>
            Accedi
          </button>
        </div>
      );
    if (section === "Notifiche")
      return (
        <Notifications
          rows={notifications}
          reload={refresh}
          notify={notify}
          userId={user!.id}
          deleting={deletingNotification}
          onDelete={(id) => {
            void removeNotification(id);
          }}
        />
      );
    if (
      section === "Servizi e prezzi" &&
      ready &&
      (role === "barber" || role === "barber_admin")
    ) {
      const ownBarber = barbers.find(
        (item) => item.user_id === user!.id && item.active,
      );
      return ownBarber ? (
        <BarberServices
          barberId={ownBarber.id}
          canEdit={role === "barber_admin"}
          notify={notify}
          refresh={refresh}
        />
      ) : (
        <Empty>Nessuna agenda associata al tuo account.</Empty>
      );
    }
    if (section === "Servizi e prezzi")
      return <ServiceCatalog services={services} />;
    if (
      section === "Prenota" &&
      user &&
      role === "client" &&
      membership !== "approved"
    ) {
      return (
        <div className="notice" role="status">
          <p>
            {membership === "rejected"
              ? "La tua richiesta di iscrizione non è stata approvata. Contatta la barberia per informazioni."
              : "Il tuo account è in attesa di approvazione. Potrai prenotare quando l’admin o un barbiere avranno approvato la tua iscrizione. Riceverai una conferma via email."}
          </p>
          <button className="secondary" onClick={refresh}>
            Aggiorna stato
          </button>
        </div>
      );
    }
    if (section === "Prenota")
      return (
        <Booking
          user={user}
          settings={settings}
          services={services}
          barbers={barbers}
          notify={notify}
          login={() => setAuth(true)}
          onBooked={() => {
            setSection("Le mie prenotazioni");
            notify("Prenotazione confermata. La trovi nelle tue prenotazioni.");
            void refresh();
          }}
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
          initialBarber={agendaContext?.barberId}
          initialDay={agendaContext?.day}
          onManualBooked={(barberId, start) => {
            const bookingDay = new Intl.DateTimeFormat("en-CA", {
              timeZone: "Europe/Rome",
              year: "numeric",
              month: "2-digit",
              day: "2-digit",
            }).format(new Date(start));
            setAgendaContext({ barberId, day: bookingDay });
            setSection("Appuntamenti");
            notify("Prenotazione inserita. Ecco l’agenda aggiornata.");
            void refresh();
          }}
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
  const resetDialog = reset && (
    <ResetPasswordDialog
      close={() => setReset(false)}
      done={() => {
        setReset(false);
        clearPasswordProof();
        notify("Password aggiornata.");
        void refresh();
      }}
    />
  );
  if (user && !auth && !reset && (!consent.ready || !consent.accepted))
    return (
      <TermsGate
        key={user.id + ":" + (consent.terms?.id ?? "checking")}
        terms={consent.terms}
        ready={consent.ready}
        error={consent.error}
        reload={consent.reload}
        onAccepted={() => {
          void refresh();
        }}
        logout={async () => {
          await detachPushDevice();
          const { error } = await supabase.auth.signOut({ scope: "local" });
          if (error) throw error;
          clearPasswordProof();
          setSection("");
          await refresh();
        }}
      />
    );
  if (user && role === "shop")
    return (
      <div className="app shop-app">
        <header className="topbar shop-topbar">
          <h1>{settings.shop_name} · Agenda</h1>
          <button
            type="button"
            className="text"
            onClick={async () => {
              try {
                await detachPushDevice();
                const { error } = await supabase.auth.signOut({
                  scope: "local",
                });
                if (error) throw error;
                clearPasswordProof();
                setSection("");
                await refresh();
              } catch {
                notify("Non riesco a uscire dall’account. Riprova.");
              }
            }}
          >
            Esci
          </button>
        </header>
        {!online && (
          <p className="offline" role="status">
            Sei offline. Collegati per aggiornare l’agenda.
          </p>
        )}
        <main className="shop-workspace">
          {loading ? (
            <p role="status">Caricamento agenda…</p>
          ) : !verified ? (
            <StaffGate email={user.email!} done={refresh} notify={notify} />
          ) : (
            <>
              <ShopAgenda
                bookingHorizonMonths={settings.booking_horizon_months ?? 6}
                onAccessChanged={refresh}
              />
              {logAllowed && (
                <button
                  type="button"
                  className="secondary shop-log-button"
                  onClick={() => setSection("Log")}
                >
                  Log
                </button>
              )}
              {logAllowed && section === "Log" && (
                <Modal wide title="Log" close={() => setSection("")}>
                  <AppointmentLog key={user.id} />
                </Modal>
              )}
            </>
          )}
        </main>
        {message && (
          <div className="toast" role="status">
            <span>{message}</span>
            <button
              onClick={() => setMessage("")}
              aria-label="Chiudi messaggio"
            >
              ×
            </button>
          </div>
        )}
        {resetDialog}
      </div>
    );
  return (
    <div className="app">
      <header className="topbar">
        <button
          className="brand"
          onClick={() => setSection("")}
          aria-label="BarberUp Home"
        >
          <img src={import.meta.env.BASE_URL + "icon.svg"} alt="" />
          <span>
            Barber<span className="gold">Up</span>
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
            className={"account" + (!user && !loading ? " guest-account" : "")}
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
        {!loading && !user && (
          <section
            className="guest-access"
            aria-labelledby="guest-access-title"
          >
            <div>
              <h2 id="guest-access-title">Non hai effettuato l’accesso</h2>
              <p>
                Accedi o crea un account per prenotare e ritrovare i tuoi
                appuntamenti.
              </p>
            </div>
            <button
              type="button"
              className="primary"
              onClick={() => setAuth(true)}
            >
              Accedi o registrati
            </button>
          </section>
        )}
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
            <span className="art-caption">BARBERUP / IL TUO STILE</span>
          </div>
        </div>
        <div className="workspace">
          <div className="section-label">
            <span>{ready ? "LA TUA AREA" : "A PORTATA DI MANO"}</span>
            <span>01 — {String(choices.length).padStart(2, "0")}</span>
          </div>
          {user && role === "client" && membership !== "approved" && (
            <div className="notice" role="status">
              <p>
                {membership === "rejected"
                  ? "La richiesta di iscrizione non è stata approvata. Contatta la barberia per informazioni."
                  : "Iscrizione in attesa di approvazione. Ti avviseremo via email quando potrai prenotare."}
              </p>
            </div>
          )}
          {loading ? (
            <p className="empty" role="status">
              Prepariamo il tuo spazio…
            </p>
          ) : staff && !verified ? (
            <StaffGate email={user!.email!} done={refresh} notify={notify} />
          ) : (
            <>
              <nav className="main-actions" aria-label="Azioni principali">
                {choices.map(([icon, title, sub], i) => (
                  <button
                    key={title}
                    className="action"
                    onClick={() => setSection(title)}
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
        </div>
      </main>
      <footer>
        <div>
          <strong>{settings.shop_name}</strong>
          <span>Un piccolo gesto. Un grande stile.</span>
          <span>Powered by MISCIANDOSKY</span>
        </div>
        <PWA />
        <span className="footer-note">PRENOTA. ARRIVA. RINNOVA.</span>
      </footer>
      {section && (
        <Modal
          key={section}
          title={section}
          actions={
            section === "Notifiche" && user && (!staff || verified) ? (
              <button
                type="button"
                className="secondary notification-delete-all"
                aria-label="Cancella tutte le notifiche"
                disabled={
                  loading || !!deletingNotification || !notifications.length
                }
                onClick={() => {
                  void removeNotification();
                }}
              >
                <TrashIcon />
                <span>
                  {deletingNotification === "all"
                    ? "Cancello…"
                    : "Cancella tutto"}
                </span>
              </button>
            ) : undefined
          }
          wide
          close={() => {
            dismissDeletionLink();
            if (
              ready &&
              role === "admin" &&
              clientChoices.some(([, title]) => title === section)
            )
              setSection("Cliente");
            else setSection("");
          }}
        >
          {loading ? (
            <p className="empty" role="status">
              Caricamento…
            </p>
          ) : staff && !verified && section !== "Profilo" ? (
            <StaffGate email={user!.email!} done={refresh} notify={notify} />
          ) : (
            content()
          )}
          {message && (
            <div className="toast" role="status">
              <span>{message}</span>
              <button
                onClick={() => setMessage("")}
                aria-label="Chiudi messaggio"
              >
                ×
              </button>
            </div>
          )}
        </Modal>
      )}
      {message && !section && (
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
          requiresApproval={settings.require_user_approval !== false}
          close={() => setAuth(false)}
          notify={notify}
          onRecovery={() => setReset(true)}
          onDone={refresh}
        />
      )}
      {legal && (
        <Modal title="Termini e condizioni" close={() => setLegal(false)}>
          <p className="legal">{terms?.body}</p>
        </Modal>
      )}
      {user && !loading && !auth && !reset && (!staff || verified) && (
        <PushOnboarding key={user.id} userId={user.id} />
      )}
      {resetDialog}
    </div>
  );
}
