# BarberCut — Handoff

Ultimo aggiornamento: 17 ottobre 2026 (Europe/Rome).

## Regola permanente del titolare

Leggere questo file prima di intervenire. Aggiornarlo a ogni modifica a BarberCut, comprese modifiche a database, Auth, template email, SMTP, impostazioni e automazioni fatte fuori dal repository. Quando possibile, includerlo nello stesso commit della modifica. Mantenere aggiornato lo stato e aggiungere una voce al registro: cosa è cambiato, verifiche eseguite, eventuali limiti o attività ancora da completare. Non presentare come verificato ciò che non è stato provato.

Lavorare direttamente su GitHub e Supabase: il titolare ha chiesto di non sviluppare in locale. Procedere autonomamente nel perimetro autorizzato, senza richiedere conferme ripetitive. Non modificare il repository staiul né il progetto Supabase MANOVELLA. Non inserire credenziali, chiavi SMTP, token di sessione o dati personali dei clienti nei file.

## Progetto e struttura

- Repository: [MISCIANDOSKY/BarberCut](https://github.com/MISCIANDOSKY/BarberCut), branch main.
- PWA: [BarberCut](https://misciandosky.github.io/BarberCut/), pubblicata con GitHub Pages.
- Supabase del progetto: wrpwitehcikplsauiwmg.
- Stack: React 19, TypeScript, Vite, supabase-js; versioni fissate nel lockfile.
- Sorgenti e migrazioni versionati su GitHub; nessun database locale. Il service worker conserva la shell della PWA, non dati personali o disponibilità.
- Struttura attuale: una barberia con più barbieri. Non è un SaaS per barberie indipendenti: servirebbero identificazione della barberia, isolamento dati/RLS, ruoli e impostazioni per ciascuna attività.
- Nessun testo legale deve essere inventato o presentato come approvato dal titolare.

## Stato delle impostazioni verificato il 17 ottobre

| Impostazione | Valore |
| --- | --- |
| Prenotazioni online | Disabilitate |
| Approvazione dei nuovi iscritti | Richiesta |
| Eliminazione account dal profilo | Abilitata |
| Preavviso minimo cancellazione | 12 ore |
| Disattivazione automatica clienti inattivi | Abilitata, 120 giorni |
| Eliminazione automatica appuntamenti vecchi | Abilitata, 40 giorni |
| Indirizzo barberia | Configurato, revisione 1 |

Le prenotazioni disabilitate sono un'impostazione corrente: non riaprirle automaticamente durante altri interventi.

## Interfaccia e navigazione

- Interfaccia italiana, responsive, tema scuro con accenti oro.
- Home cliente: Prenota, Servizi e prezzi, Le mie prenotazioni, Informazioni.
- Le funzioni si aprono come schermate complete, mostrando solo la funzione selezionata, con freccia indietro. Non devono tornare a essere riquadri in fondo alla pagina o finestre centrali con la home visibile dietro.
- Profilo a schermata completa; pulsante Esci sotto Salva profilo.
- Footer: “Un piccolo gesto. Un grande stile.” e “Powered by MISCIANDOSKY”.
- Errori OTP errato/scaduto visibili in rosso.
- Errore invio codice: “Errore nell’invio, riprovare fra qualche minuto.”; non mostrare istruzioni tecniche Supabase al cliente.

## Registrazione, accesso e messaggi email

- Login con password e login senza password tramite codice email; il codice può essere inserito nell'app oppure si può usare il link.
- Richiesta codice di accesso riservata ad account già esistenti; registrazione separata, reinvio con attesa di 60 secondi.
- Admin e barbiere richiedono una sessione verificata via email; autorizzazione staff associata alla sessione e limitata nel tempo. I ruoli sono nel database, mai attribuiti da user_metadata.
- Modelli Supabase di conferma registrazione e accesso in italiano, con codice dinamico {{ .Token }} visibile e link alternativo.
- Modello recupero password italiano: oggetto “BarberCut — Reimposta la tua password”, istruzioni e pulsante per reimpostarla.
- SMTP Brevo configurato in Supabase, mittente visualizzato BarberCut. La consegna tramite Brevo è stata osservata nello screenshot del titolare; i template inglesi segnalati sono stati corretti successivamente.
- Il template Magic Link gestisce anche avvisi di inattività e approvazione iscrizione, tramite metadati temporanei di presentazione. Non usarli per autorizzazioni.
- Registrazioni ammesse anche senza termini pubblicati. Con termini pubblicati, checkbox:
  “Dichiaro di aver letto e accettato i termini e condizioni di utilizzo e di aver preso visione dell'informativa sul trattamento dei dati personali (privacy policy)”.
- Eliminazione account abilitata su richiesta: conferma email, protezione ultimo admin, cancellazione appuntamenti futuri e conservazione dello storico anonimizzato.
- Non sono state eliminate utenze reali né inviate email di prova a clienti reali per verificare questi flussi.

## Clienti e approvazione iscrizioni

- In Manutenzione: checkbox “Richiedi approvazione per i nuovi utenti”, selezionata di default.
- Se attiva, le nuove iscrizioni hanno stato In attesa; se disattivata, quelle successive sono approvate automaticamente. Il cambio non converte gli utenti già in attesa o rifiutati.
- I clienti esistenti sono stati conservati come approvati.
- Admin e barbiere verificato con associazione attiva hanno il pulsante Gestisci utenti: In attesa, Approvati, Rifiutati.
- Approva/Rifiuta consentiti per iscrizioni pendenti con email verificata. Il cliente non può approvarsi modificando il profilo o i metadati.
- Clienti in attesa/rifiutati non possono prenotare; controllo anche nel database, non solo nell'interfaccia.
- Approvazione: email italiana “Sei stato approvato!” con “Prenota il tuo servizio”, collegata a ?book=1. L'apertura prenotazione continua a richiedere accesso e stato approvato.
- Invio tramite coda privata ed Edge Function registration-approved, tentativo immediato e recupero ogni 5 minuti, fino a 6 tentativi con intervalli di 30 minuti. Decisioni duplicate non generano più email.
- Nessuna email di rifiuto richiesta o implementata.

## Prenotazioni e agenda

- Disponibilità calcolata dal server, fuso Europe/Rome, scatti di 15 minuti; verifica dell'intera durata del servizio.
- Limiti: massimo 5 appuntamenti futuri per cliente e prenotazione entro 3 mesi.
- Orari settimanali, turni, eccezioni per data, festività nazionali e Pasquetta; le chiusure prevalgono sulle aperture.
- Vincolo database contro sovrapposizioni tra appuntamenti e blocchi dello stesso barbiere, con lock per richieste concorrenti.
- Nome e prezzo del servizio prenotato rimangono nello storico anche dopo modifiche al catalogo.
- Nuova prenotazione manuale staff: nome e cognome obbligatori, telefono facoltativo, nessuna email obbligatoria. Possibili clienti ospiti senza account.
- Il barbiere può bloccare soltanto la propria agenda.
- Promemoria interni 24 ore e 1 ora prima, deduplicati; nessun promemoria email appuntamento o Web Push implementato.

## Barbieri, servizi e ruoli

- Creare un barbiere associato a un account assegna automaticamente il ruolo Barbiere, preservando eventuale ruolo Admin.
- Eliminare il barbiere riporta l'account a Cliente quando non rimangono associazioni attive; revoca le sessioni staff e preserva gli admin.
- Disattivazione temporanea distinta dall'eliminazione.
- Un account di barbiere eliminato può essere associato nuovamente: indice univoco parziale sulle agende non eliminate.
- Admin: Modifica, Disattiva/Riattiva, Elimina, disposti uno sotto l'altro per servizi e barbieri.
- Eliminazione catalogo tramite archiviazione: storico preservato; barbiere con appuntamenti futuri confermati non eliminabile.
- Barbiere: aggiunta, modifica, eliminazione dei propri servizi/prezzi. Se un servizio è condiviso, la modifica crea la variante per quel barbiere senza alterare gli altri o le prenotazioni già effettuate.

## Informazioni barberia

- Pulsante Informazioni dopo Le mie prenotazioni: indirizzo, collegamento Google Maps, orari dei barbieri attivi ed eccezioni dei prossimi 30 giorni.
- L'indirizzo si modifica dal profilo solo come admin o barbiere verificato associato attivamente.
- Primo salvataggio senza conferma aggiuntiva. Dalla modifica successiva:
  “Sei sicuro che vuoi modificare l’indirizzo della barberia?”.
- Controllo revisione sul server per evitare che due modifiche simultanee si sovrascrivano.
- Informazioni pubbliche separate da dati personali, note e identificativi degli account.

## Manutenzione, inattività e automazioni

- Manutenzione giornaliera alle 03:15 UTC; soglie numeriche modificabili, impostazioni salvate atomicamente insieme alla politica iscrizioni.
- Disattiva solo clienti inattivi: admin e barbieri sono esclusi, come gli account associati ad agende e quelli con appuntamenti futuri confermati.
- Login/sessione attiva e prenotazioni del cliente aggiornano l'attività. Disattivazione con ban Auth e revoca sessioni; non elimina il profilo. Admin può riattivare.
- Avvisi email 30, 15 e 7 giorni prima: invito a prenotare oppure accedere dal link per mantenere attivo il profilo. Leggere l'email da solo non rinnova l'attività.
- Primo ciclo concede il preavviso completo; niente disattivazione senza avviso finale inviato da almeno 7 giorni. Se l'invio fallisce, la disattivazione viene rinviata.
- Coda avvisi ogni 15 minuti, fino a 20 invii per ciclo, retry e annullamento dei vecchi avvisi al ritorno dell'utente.
- Edge Function inactivity-warning con token casuale monouso a scadenza; destinatari e operazioni privilegiati controllati dal server.
- Pulizia appuntamenti: elimina quelli terminati prima della mezzanotte italiana di oggi meno 40 giorni. Preserva appuntamenti recenti/futuri, confine e blocchi orari. Eliminazione effettiva, non semplice archiviazione.
- Cron attivi: barbercut-appointment-reminders (5 minuti), barbercut-daily-maintenance (03:15 UTC), barbercut-inactivity-warning-dispatch (15 minuti), barbercut-registration-approved-email (5 minuti).
- Workflow GitHub database-health ogni 6 ore: lettura pubblica minima reale su Supabase. Non garantisce disponibilità continua del piano Free; possibili sospensione Supabase per inattività e disabilitazione pianificazioni GitHub dopo prolungata inattività del repository.
- Chiave SMTP soggetta alle regole/scadenze Brevo: verificare in caso di mancati invii senza copiare segreti nei documenti.

## Sicurezza e implementazione

- RLS e grant limitati; tabelle private per sessioni staff, attività, code, manutenzione e approvazioni.
- Funzioni privilegiate private con search_path esplicito e controlli server; wrapper pubblici con permessi minimi.
- Edge Functions: staff-email-verification, delete-account, inactivity-warning, registration-approved.
- Per le due code email, claim/finish riservati a service_role; endpoint con verifica propria del token monouso. Non rendere selezionabile il destinatario da chiamanti esterni.
- Export JSON admin disponibile; non sostituisce un backup PostgreSQL completo comprendente Auth.
- Nessun segreto SMTP/service_role nel frontend o nei documenti.

## Verifiche e limiti noti

- CI GitHub: lockfile, installazione, formattazione, TypeScript, build, test e pubblicazione Pages.
- Ultima CI funzionale prima di questo riepilogo: [run 39018278190](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39018278190), completata con successo.
- Test SQL transazionali con rollback: disponibilità, RLS/limiti, cancellazione account, flussi barbiere/ospiti/servizi, manutenzione, inattività, informazioni barberia, riuso account barbiere, approvazione nuovi iscritti.
- Controllati approvazione/rifiuto, blocco prenotazioni pendenti, permessi staff, email non verificata, idempotenza, code/token e salvataggio impostazioni.
- Test Node su date, richieste concorrenti UI, PWA e healthcheck.
- Non eseguiti test fisici completi su Safari iPhone/Chrome Android né prove in casella email reale per approvazioni/avvisi dopo gli ultimi aggiornamenti.
- Il dispatcher inattività aveva fallito alle 08:30 UTC del 17 ottobre per collisione tra alias SQL e variabile PL/pgSQL. Corretto in migrazione 20261017083644 e verificato manualmente senza destinatari; al controllo delle 08:40 UTC il successivo cron delle 08:45 non era ancora avvenuto. Non confondere quel precedente errore con una nuova regressione; verificare il prossimo esito schedulato.
- Allo stesso controllo, ultimi cron promemoria, manutenzione giornaliera e approvazioni riusciti.

## Dove intervenire

- src/App.tsx: navigazione, stato globale, ruoli e impostazioni.
- src/features/Auth.tsx: accesso, OTP, registrazione e gate staff.
- src/features/Account.tsx: profilo, appuntamenti, notifiche, eliminazione.
- src/features/Admin.tsx: amministrazione e manutenzione.
- src/features/ManageUsers.tsx: approvazione iscrizioni.
- src/features/Manage.tsx, Booking.tsx, BarberServices.tsx: agenda, prenotazioni, servizi.
- src/features/Information.tsx, BarberAddress.tsx: informazioni e indirizzo.
- src/components/UI.tsx: schermate e componenti condivisi.
- supabase/migrations: migrazioni corrispondenti alle versioni registrate sul progetto remoto.
- supabase/functions, supabase/tests: funzioni Edge e regressioni SQL.
- docs: documentazione specifica di email, Brevo, manutenzione, inattività, approvazioni, disponibilità database, flussi barbieri e informazioni barberia.
- .github/workflows: pubblicazione e controllo periodico database.

docs/VERIFICA.md contiene verifiche e limiti della prima versione; alcune sue note residue sono storiche e superate da questo handoff e dai documenti specifici successivi. Consultare sempre codice e impostazioni effettive prima di assumere che un vecchio limite sia ancora valido.

## Registro delle modifiche

### 16–17 ottobre 2026 — Riepilogo iniziale ricostruito

Creata e pubblicata PWA con Supabase; aggiunti autenticazione OTP, template italiani e Brevo, ruoli e sessioni staff, prenotazioni e agenda, gestione servizi/barbieri, schermate complete, profilo/logout, eliminazione account, indirizzo e informazioni, manutenzione automatica e avvisi, healthcheck remoto. Corretto riuso degli account barbiere dopo eliminazione. Aggiunti approvazione iscrizioni e invio email al cliente approvato. Le sezioni sopra distinguono funzioni implementate, stato live e verifiche ancora mancanti.

### 17 ottobre 2026 — Handoff permanente

Creati HANDOFF.md e AGENTS.md su richiesta del titolare, con obbligo di aggiornare il riepilogo a ogni intervento. Aggiornato README per allinearlo alle funzioni correnti. Nessuna modifica a dati o impostazioni operative in questo intervento. Verificati repository, configurazione e ultimi esiti cron; sola documentazione.
