import { Children, isValidElement, useEffect, useId, useRef, useState } from "react";
import type { ChangeEvent, ReactNode, SelectHTMLAttributes } from "react";
import { Modal } from "./UI";

type Option = { value: string; label: ReactNode; disabled: boolean };
export function AppSelect({ children, value, defaultValue, onChange, name, required, disabled, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  const options: Option[] = Children.toArray(children).flatMap((child) => {
    if (!isValidElement<{value?: string | number; children?: ReactNode; disabled?: boolean}>(child) || child.type !== "option") return [];
    return [{ value: String(child.props.value ?? child.props.children ?? ""), label: child.props.children, disabled: !!child.props.disabled }];
  });
  const [local, setLocal] = useState(String(defaultValue ?? options[0]?.value ?? ""));
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const dialogId = useId();
  const current = value === undefined ? local : String(value);
  const option = options.find((item) => item.value === current);
  useEffect(() => {
    if (value === undefined && !options.some((item) => item.value === local))
      setLocal(String(defaultValue ?? options[0]?.value ?? ""));
  }, [options.map((item) => item.value).join("\0"), value, local, defaultValue]);
  useEffect(() => {
    const form = trigger.current?.closest("form");
    const reset = () => setLocal(String(defaultValue ?? options[0]?.value ?? ""));
    form?.addEventListener("reset", reset);
    return () => form?.removeEventListener("reset", reset);
  }, [defaultValue, options.map((item) => item.value).join("\0")]);
  const choose = (next: string) => {
    setOpen(false);
    if (value === undefined) setLocal(next);
    onChange?.({ target: { value: next, name }, currentTarget: { value: next, name } } as ChangeEvent<HTMLSelectElement>);
  };
  return (
    <span className="app-control app-select">
      <input className="app-validation-field" data-app-control="true" name={name} value={current} onChange={() => {}} required={required} disabled={disabled} tabIndex={-1} aria-hidden="true" />
      <button ref={trigger} type="button" id={props.id} className={"app-select-trigger " + (props.className || "")} disabled={disabled} aria-label={props["aria-label"]} aria-labelledby={props["aria-labelledby"]} aria-haspopup="dialog" aria-expanded={open} aria-controls={open ? dialogId : undefined} onClick={() => setOpen(true)}>
        <span>{option?.label ?? "Scegli un’opzione"}</span><span aria-hidden="true">⌄</span>
      </button>
      {open && <Modal title={props["aria-label"] || "Scegli un’opzione"} close={() => setOpen(false)} className="app-options-dialog">
        <div id={dialogId} className="app-options" role="group" aria-label="Opzioni disponibili">
          {options.map((item) => <button type="button" key={item.value} className={"app-option " + (current === item.value ? "selected" : "")} aria-pressed={current === item.value} disabled={item.disabled} onClick={() => choose(item.value)}><span>{item.label}</span>{current === item.value && <span aria-hidden="true">✓</span>}</button>)}
        </div>
        <button type="button" className="secondary" onClick={() => setOpen(false)}>Annulla</button>
      </Modal>}
    </span>
  );
}
