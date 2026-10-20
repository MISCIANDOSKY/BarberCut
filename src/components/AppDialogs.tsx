import { useEffect, useSyncExternalStore } from "react";
import { Modal } from "./UI";

type Question = { id: number; message: string; confirmation: boolean; resolve: (answer: boolean) => void };
let questions: Question[] = [];
let sequence = 0;
const listeners = new Set<() => void>();
const publish = () => listeners.forEach((listener) => listener());
const subscribe = (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
const snapshot = () => questions[0] || null;
function ask(message: string, confirmation: boolean) {
  return new Promise<boolean>((resolve) => {
    questions = [...questions, { id: ++sequence, message, confirmation, resolve }];
    publish();
  });
}
export const confirmInApp = (message: string) => ask(message, true);
export const informInApp = (message: string) => ask(message, false);
function answer(value: boolean) {
  const current = questions[0];
  if (!current) return;
  questions = questions.slice(1);
  current.resolve(value);
  publish();
}
export function AppDialogs() {
  const question = useSyncExternalStore(subscribe, snapshot);
  useEffect(() => {
    let handling = false;
    const invalid = (event: Event) => {
      event.preventDefault();
      const field = event.target;
      if (handling || !(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement || field instanceof HTMLSelectElement)) return;
      handling = true;
      const message = field.validity.valueMissing ? "Compila il campo richiesto per continuare." :
        field.validity.typeMismatch ? "Controlla il formato del dato inserito." :
        field.validity.rangeUnderflow || field.validity.rangeOverflow ? "Il valore è fuori dall’intervallo consentito." :
        field.validationMessage && field.dataset.appControl ? field.validationMessage :
        "Controlla il campo indicato e inserisci un valore valido.";
      void informInApp(message).then(() => {
        handling = false;
        if (!field.isConnected) return;
        const control = field.closest(".app-control")?.querySelector<HTMLButtonElement>("button");
        (control || field).focus();
      });
    };
    document.addEventListener("invalid", invalid, true);
    return () => document.removeEventListener("invalid", invalid, true);
  }, []);
  return question ? (
    <Modal key={question.id} title={question.confirmation ? "Conferma" : "Controlla i dati"} close={() => answer(false)} className="app-message-dialog">
      <p>{question.message}</p>
      <div className="two">
        {question.confirmation && <button type="button" className="secondary" onClick={() => answer(false)}>No, annulla</button>}
        <button type="button" className="primary" onClick={() => answer(true)}>{question.confirmation ? "Sì, conferma" : "Ho capito"}</button>
      </div>
    </Modal>
  ) : null;
}
