import { useState } from "react";
import { Empty, Modal } from "../components/UI";
import { euro } from "../lib/api";
import type { Row } from "../lib/api";

export default function ServiceCatalog({ services }: { services: Row[] }) {
  const [selected, setSelected] = useState<Row | null>(null);
  if (!services.length) return (
    <Empty>Il catalogo è in preparazione. Torna presto per scoprire servizi e prezzi.</Empty>
  );
  return (
    <>
      <div className="service-list">
        {services.map((service) => (
          <article className="service" key={service.id}>
            <span className="service-summary">
              <strong>{service.name}</strong>
              <small>{service.duration_minutes} minuti</small>
            </span>
            <span className="service-price-info">
              <strong>{euro(service.price)}</strong>
              <button type="button" className="service-info"
                aria-label={"Descrizione di " + service.name}
                onClick={() => setSelected(service)}>
                <span aria-hidden="true">ⓘ</span>
              </button>
            </span>
          </article>
        ))}
      </div>
      {selected && (
        <Modal title={selected.name} wide close={() => setSelected(null)}>
          <p className="service-description">{selected.description?.trim() || "Nessuna descrizione disponibile."}</p>
        </Modal>
      )}
    </>
  );
}
