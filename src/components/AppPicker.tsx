import { useEffect, useRef, useState } from "react";
import type { ChangeEvent, InputHTMLAttributes } from "react";
import { Modal } from "./UI";
import { AppSelect } from "./AppSelect";

const pad = (n: number) => String(n).padStart(2, "0");
const localDay = () => {
  const d = new Date();
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
};
const months = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"];
type PickerType = "date" | "time" | "datetime-local" | "color";
export function AppPicker({ type = "date", value, defaultValue, onChange, name, required, disabled, min, max, step, ...props }: InputHTMLAttributes<HTMLInputElement> & {type?: PickerType}) {
  const [local, setLocal] = useState(String(defaultValue ?? ""));
  const current = value === undefined ? local : String(value);
  const [open, setOpen] = useState(false);
  const [draftDay, setDraftDay] = useState("");
  const [draftTime, setDraftTime] = useState("");
  const [draftColor, setDraftColor] = useState("#c6a66b");
  const [year, setYear] = useState(2026);
  const [month, setMonth] = useState(0);
  const [yearText, setYearText] = useState("2026");
  const field = useRef<HTMLInputElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const withDate = type === "date" || type === "datetime-local";
  const withTime = type === "time" || type === "datetime-local";
  const minText = min === undefined ? "" : String(min);
  const maxText = max === undefined ? "" : String(max);
  useEffect(() => {
    const invalidRange = current && ((minText && current < minText) || (maxText && current > maxText));
    field.current?.setCustomValidity(invalidRange ? "Scegli un valore nell’intervallo consentito." : "");
  }, [current, minText, maxText]);
  useEffect(() => {
    const form = trigger.current?.closest("form");
    const reset = () => setLocal(String(defaultValue ?? ""));
    form?.addEventListener("reset", reset);
    return () => form?.removeEventListener("reset", reset);
  }, [defaultValue]);
  const start = () => {
    const day = (withDate && current.slice(0, 10)) || localDay();
    const bounded = minText && day < minText.slice(0, 10) ? minText.slice(0, 10) : maxText && day > maxText.slice(0, 10) ? maxText.slice(0, 10) : day;
    setDraftDay(bounded);
    setYear(Number(bounded.slice(0, 4)));
    setYearText(bounded.slice(0, 4));
    setMonth(Number(bounded.slice(5, 7)) - 1);
    setDraftTime((type === "time" ? current : current.slice(11, 16)) || "09:00");
    setDraftColor(current || "#c6a66b");
    setOpen(true);
  };
  const commit = (next: string) => {
    if (value === undefined) setLocal(next);
    setOpen(false);
    onChange?.({ target: { value: next, name }, currentTarget: { value: next, name } } as ChangeEvent<HTMLInputElement>);
  };
  const dateAllowed = (day: string) => (!minText || day >= minText.slice(0, 10)) && (!maxText || day <= maxText.slice(0, 10));
  const goMonth = (delta: number) => {
    const date = new Date(Date.UTC(year, month + delta, 1));
    const nextYear = date.getUTCFullYear();
    if (nextYear < 1900 || nextYear > 9999) return;
    setYear(nextYear); setYearText(String(nextYear)); setMonth(date.getUTCMonth());
  };
  const first = new Date(Date.UTC(year, month, 1));
  const leading = (first.getUTCDay() + 6) % 7;
  const dayCount = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const days = Array.from({ length: dayCount }, (_, i) => year + "-" + pad(month + 1) + "-" + pad(i + 1));
  const minuteStep = step && step !== "any" ? Math.max(1, Math.min(60, Number(step) / 60)) : 1;
  const minutes = Array.from({ length: Math.ceil(60 / minuteStep) }, (_, i) => pad(i * minuteStep)).filter((minute) => Number(minute) < 60);
  const hour = draftTime.slice(0, 2), minute = draftTime.slice(3, 5);
  const draft = type === "date" ? draftDay : type === "time" ? draftTime : type === "datetime-local" ? draftDay + "T" + draftTime : draftColor;
  const valid = !!draft && (!withDate || dateAllowed(draftDay)) && (!withTime || /^\d{2}:\d{2}$/.test(draftTime)) &&
    (type !== "color" || /^#[0-9a-f]{6}$/i.test(draftColor)) && (!minText || draft >= minText) && (!maxText || draft <= maxText);
  const label = type === "date" ? "Scegli il giorno" : type === "time" ? "Scegli l’orario" : type === "datetime-local" ? "Scegli giorno e orario" : "Scegli il colore";
  const display = current ? type === "color" ? current : type === "time" ? current.slice(0, 5) :
    current.slice(8, 10) + "/" + current.slice(5, 7) + "/" + current.slice(0, 4) + (type === "datetime-local" ? " · " + current.slice(11, 16) : "") : label;
  return (
    <span className="app-control app-picker">
      <input ref={field} className="app-validation-field" data-app-control="true" name={name} value={current} onChange={() => {}} required={required} disabled={disabled} tabIndex={-1} aria-hidden="true" />
      <button ref={trigger} id={props.id} type="button" className="app-picker-trigger" disabled={disabled} aria-label={props["aria-label"] || label + (current ? ": " + display : "")} aria-haspopup="dialog" aria-expanded={open} onClick={start}>
        <span>{display}</span>{type === "color" ? <span className="app-color-preview" style={{ background: current || "#c6a66b" }} /> : <span aria-hidden="true">{withDate ? "▦" : "◷"}</span>}
      </button>
      {open && <Modal title={label} close={() => setOpen(false)} className="app-picker-dialog">
        {withDate && <>
          <div className="app-calendar-heading">
            <button type="button" className="secondary" aria-label="Mese precedente" onClick={() => goMonth(-1)}>←</button>
            <AppSelect aria-label="Mese" value={month} onChange={(e) => setMonth(Number(e.target.value))}>{months.map((item, i) => <option key={item} value={i}>{item}</option>)}</AppSelect>
            <label className="app-calendar-year">Anno<input type="text" inputMode="numeric" maxLength={4} value={yearText} onChange={(e) => { const text = e.target.value.replace(/\D/g, ""); setYearText(text); const n = Number(text); if (n >= 1900 && n <= 9999) setYear(n); }} onBlur={() => { if (Number(yearText) < 1900 || Number(yearText) > 9999) setYearText(String(year)); }} /></label>
            <button type="button" className="secondary" aria-label="Mese successivo" onClick={() => goMonth(1)}>→</button>
          </div>
          <div className="app-calendar-grid" role="group" aria-label={months[month] + " " + year}>
            {["L", "M", "M", "G", "V", "S", "D"].map((day, i) => <span key={i} className="app-calendar-weekday" aria-hidden="true">{day}</span>)}
            {Array.from({length: leading}, (_, i) => <span key={"empty" + i} />)}
            {days.map((day, i) => <button key={day} type="button" className={draftDay === day ? "selected" : ""} disabled={!dateAllowed(day)} aria-label={(i + 1) + " " + months[month] + " " + year} aria-pressed={draftDay === day} onClick={() => setDraftDay(day)}>{i + 1}</button>)}
          </div>
          <p className="muted">Giorno selezionato: {draftDay.slice(8, 10)}/{draftDay.slice(5, 7)}/{draftDay.slice(0, 4)}</p>
        </>}
        {withTime && <div className="two">
          <label>Ore<AppSelect aria-label="Ore" value={hour} onChange={(e) => setDraftTime(e.target.value + ":" + minute)}>{Array.from({length: 24}, (_, i) => <option key={i} value={pad(i)}>{pad(i)}</option>)}</AppSelect></label>
          <label>Minuti<AppSelect aria-label="Minuti" value={minute} onChange={(e) => setDraftTime(hour + ":" + e.target.value)}>{[...new Set([...minutes, minute])].sort().map((m) => <option key={m} value={m}>{m}</option>)}</AppSelect></label>
        </div>}
        {type === "color" && <>
          <div className="app-color-options">{["#c6a66b", "#c18e55", "#c5a878", "#98b18c", "#79a5c4", "#c18b9f", "#d2d2d2", "#e5b74f"].map((color) => <button key={color} type="button" style={{background: color}} aria-label={"Colore " + color} aria-pressed={draftColor === color} onClick={() => setDraftColor(color)}>{draftColor === color ? "✓" : ""}</button>)}</div>
          <label>Codice colore<input type="text" value={draftColor} maxLength={7} onChange={(e) => setDraftColor(e.target.value)} placeholder="#c6a66b" /></label>
        </>}
        <div className="two">
          <button type="button" className="secondary" onClick={() => setOpen(false)}>Annulla</button>
          <button type="button" className="primary" disabled={!valid} onClick={() => commit(draft)}>Conferma</button>
        </div>
        {!required && current && <button type="button" className="text" onClick={() => commit("")}>Svuota campo</button>}
      </Modal>}
    </span>
  );
}
