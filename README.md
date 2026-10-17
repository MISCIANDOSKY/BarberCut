# BarberCut

PWA per una barberia con più barbieri, realizzata con React, TypeScript e Supabase e pubblicata su GitHub Pages.

**[Apri BarberCut](https://misciandosky.github.io/BarberCut/)** · **[Handoff e stato del progetto](HANDOFF.md)**

## Prima di intervenire

Leggere [HANDOFF.md](HANDOFF.md) e [AGENTS.md](AGENTS.md). Per richiesta del titolare, aggiornare l'handoff a ogni modifica, anche di configurazioni remote. Lavorare su GitHub e Supabase senza sviluppo locale.

## Funzioni

- Registrazione, accesso con password o codice email, recupero password, profilo, logout ed eliminazione account.
- Email italiane con OTP e link alternativo; SMTP Brevo configurato.
- Approvazione dei nuovi iscritti gestita da admin e barbiere.
- Prenotazioni, disponibilità Europe/Rome, turni, eccezioni, festività e protezione dalle sovrapposizioni.
- Agenda barbiere, prenotazioni manuali senza email obbligatoria, blocchi della propria agenda e gestione servizi/prezzi.
- Admin per utenti, barbieri, servizi, impostazioni e manutenzione automatica.
- Informazioni barberia e indirizzo modificabile da admin o barbiere associato.
- Avvisi di inattività e promemoria interni; schermate complete adatte all'uso mobile.

## Operatività e sicurezza

La CI installa dal lockfile, formatta, controlla TypeScript, esegue build e test e pubblica la PWA. La cache conserva la shell, non dati personali o disponibilità.

Ruoli, permessi, approvazioni e vincoli prenotazione sono verificati nel database. Le credenziali privilegiate restano su Supabase; non inserirle nel repository.

Le impostazioni live, le verifiche eseguite e i limiti sono riportati nell'[handoff](HANDOFF.md). Il progetto attuale serve una sola barberia; non isola più attività indipendenti come SaaS. L'export JSON applicativo non sostituisce un backup completo. Il controllo periodico del database non garantisce disponibilità continua sul piano Free.

## Sorgenti

- src: interfaccia e flussi applicativi.
- supabase/migrations: schema e funzioni versionati.
- supabase/functions: funzioni Edge.
- supabase/tests e tests: verifiche automatiche.
- scripts e .github/workflows: PWA, build, pubblicazione e healthcheck.
- docs: documentazione specifica delle funzioni.

Le migrazioni corrispondono alle versioni registrate nel progetto Supabase remoto.
