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
      <div className="content-stack">{children}</div>
    </section>
  );
}
export function Modal({
  title,
  children,
  close,
  wide = false,
  className = "",
  actions,
}: {
  title: string;
  children: ReactNode;
  close: () => void;
  wide?: boolean;
  className?: string;
  actions?: ReactNode;
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
      className={
        [wide ? "feature-dialog" : "", className].filter(Boolean).join(" ") ||
        undefined
      }
      onCancel={close}
      onClick={(e) => {
        if (!wide && e.target === e.currentTarget) close();
      }}
    >
      <header className={actions ? "has-actions" : undefined}>
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
        {actions && <div className="screen-header-actions">{actions}</div>}
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
      {wide ? (
        <div className="feature-content content-stack">{children}</div>
      ) : (
        <div className="dialog-content content-stack">{children}</div>
      )}
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

export function TrashIcon() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M3 6h18M9 6V4h6v2M5 6l1 14h12l1-14M10 10v6m4-6v6" />
    </svg>
  );
}
