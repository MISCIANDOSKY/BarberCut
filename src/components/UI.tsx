import { useEffect, useRef } from "react";
import type { ReactNode } from "react";
export function Panel({
  title,
  children,
  back,
}: {
  title: string;
  children: ReactNode;
  back?: () => void;
}) {
  return (
    <section className="panel">
      <header className="panel-heading">
        {back && (
          <button className="back" onClick={back} aria-label="Torna alla Home">
            ←
          </button>
        )}
        <h2>{title}</h2>
      </header>
      {children}
    </section>
  );
}
export function Modal({
  title,
  children,
  close,
  wide = false,
  className = "",
}: {
  title: string;
  children: ReactNode;
  close: () => void;
  wide?: boolean;
  className?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    d?.showModal();
    return () => d?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className={[wide ? "feature-dialog" : "", className].filter(Boolean).join(" ") || undefined}
      onCancel={close}
      onClick={(e) => {
        if (!wide && e.target === e.currentTarget) close();
      }}
    >
      <header>
        {wide && (
          <button
            type="button"
            className="back"
            onClick={close}
            aria-label="Torna indietro"
          >
            ←
          </button>
        )}
        <h2>{title}</h2>
        {!wide && (
          <button
            type="button"
            className="back"
            onClick={close}
            aria-label="Chiudi finestra"
          >
            ×
          </button>
        )}
      </header>
      {wide ? <div className="feature-content">{children}</div> : children}
    </dialog>
  );
}
export function Empty({ children }: { children: ReactNode }) {
  return <p className="empty">{children}</p>;
}
export function Field({
  label,
  name,
  type = "text",
  value,
  onChange,
  required = true,
}: {
  label: string;
  name: string;
  type?: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
}) {
  return (
    <label>
      {label}
      <input
        name={name}
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        required={required}
      />
    </label>
  );
}
