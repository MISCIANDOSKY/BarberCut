import { useEffect, useState } from "react";
import { Empty } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";

const weekdays = [
  "Domenica",
  "Lunedì",
  "Martedì",
  "Mercoledì",
  "Giovedì",
  "Venerdì",
  "Sabato",
];
const time = (value: string) => value.slice(0, 5);

export default function Information() {
  const [data, setData] = useState<Row | null>(null);
  const [error, setError] = useState("");
  async function load() {
    setError("");
    try {
      setData(await result<Row>(supabase.rpc("shop_information")));
    } catch (e) {
      setError(friendly(e));
    }
  }
  useEffect(() => {
    void load();
  }, []);
  if (error)
    return (
      <>
        <p className="form-error" role="alert">
          {error}
        </p>
        <button className="secondary" onClick={load}>
          Riprova
        </button>
      </>
    );
  if (!data) return <p role="status">Caricamento informazioni…</p>;
  return (
    <>
      <h3>{data.shop_name}</h3>
      <section className="shop-address">
        <h3>Dove siamo</h3>
        {data.address ? (
          <>
            <address>{data.address}</address>
            <a
              className="secondary"
              href={
                "https://www.google.com/maps/search/?api=1&query=" +
                encodeURIComponent(data.address)
              }
              target="_blank"
              rel="noopener noreferrer"
            >
              Apri sulla mappa
            </a>
          </>
        ) : (
          <p className="muted">
            L’indirizzo della barberia non è ancora stato inserito.
          </p>
        )}
      </section>
      <h3>Orari</h3>
      <p className="muted">
        Gli orari sono aggiornati dai barbieri. Gli intervalli di mattina e
        pomeriggio sono indicati separatamente. Festività italiane: chiuso.
      </p>
      {!data.barbers.length && (
        <Empty>Gli orari della barberia sono in preparazione.</Empty>
      )}
      {data.barbers.map((barber: Row) => {
        const dates: string[] = [
          ...new Set<string>(barber.exceptions.map((item: Row) => item.day)),
        ];
        return (
          <section key={barber.id} className="shop-hours">
            <h3>{barber.name}</h3>
            {barber.hours.length ? (
              <dl>
                {[1, 2, 3, 4, 5, 6, 0].map((day) => {
                  const intervals = barber.hours.filter(
                    (item: Row) => item.weekday === day,
                  );
                  return (
                    <div className="shop-hours-row" key={day}>
                      <dt>{weekdays[day]}</dt>
                      <dd>
                        {intervals.length
                          ? intervals.map((item: Row) => (
                              <span className="shop-hours-interval" key={item.id || item.opens + "-" + item.closes}>
                                {time(item.opens)}–{time(item.closes)}
                              </span>
                            ))
                          : "Chiuso"}
                      </dd>
                    </div>
                  );
                })}
              </dl>
            ) : (
              <p className="muted">Orari non ancora impostati.</p>
            )}
            {!!dates.length && (
              <>
                <h4>Variazioni nei prossimi 30 giorni</h4>
                <dl>
                  {dates.map((day) => {
                    const changes = barber.exceptions.filter(
                      (item: Row) => item.day === day,
                    );
                    return (
                      <div className="shop-hours-row" key={day}>
                        <dt>
                          {new Date(day + "T12:00:00").toLocaleDateString(
                            "it-IT",
                            {
                              weekday: "short",
                              day: "numeric",
                              month: "short",
                            },
                          )}
                        </dt>
                        <dd>
                          {changes.some((item: Row) => item.closed)
                            ? "Chiuso"
                            : changes.map((item: Row) => (
                                <span className="shop-hours-interval" key={item.id || item.opens + "-" + item.closes}>
                                  {time(item.opens)}–{time(item.closes)}
                                </span>
                              ))}
                        </dd>
                      </div>
                    );
                  })}
                </dl>
              </>
            )}
          </section>
        );
      })}
    </>
  );
}
