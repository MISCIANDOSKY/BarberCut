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
- Catalogo cliente: nome e durata senza descrizione inline; icona informativa color accento giallo accanto al prezzo apre la descrizione a schermata completa, con freccia indietro al catalogo. Disponibile anche nell’area Cliente dell’admin.
- In fondo alla home admin: tasto Cliente che apre gli stessi quattro comandi cliente, senza cambio ruolo o account. La freccia dalle funzioni personali riporta al menu Cliente; dal menu Cliente torna alla home admin. Le prenotazioni personali usano il client_id dell’admin e rispettano il normale flusso personale.
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

- Admin > Configurazione: unica checkbox “Accetta i nuovi clienti senza approvazione”, subito prima di Apri le prenotazioni online. Rimossa da Manutenzione.
- Nel Profilo del barbiere verificato con agenda attiva associata: Iscrizione nuovi clienti, stessa unica checkbox e salvataggio dedicato. La politica è unica per tutta la barberia; al barbiere è consentito modificare solo questo flag, non le altre impostazioni di manutenzione.
- Spunta attiva = accettazione automatica dopo verifica email (require_user_approval=false); spunta disattiva = richiesta approvazione (require_user_approval=true). Il cambio non converte gli utenti già in attesa o rifiutati.
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
- Dopo una prenotazione personale riuscita, apertura automatica di Le mie prenotazioni e aggiornamento elenco, anche per l’admin dall’area Cliente. I salvataggi manuali staff continuano invece a tornare all’agenda.
- Orari settimanali, turni, eccezioni per data, festività nazionali e Pasquetta; le chiusure prevalgono sulle aperture.
- Orari di lavoro: riepilogo di tutti i sette giorni con stato Chiuso esplicito. Nel giorno selezionato, checkbox Chiuso subito sopra il pulsante Aggiungi intervallo (o Salva giorno di chiusura) disabilita i campi orario; Salva giorno di chiusura rimuove gli intervalli settimanali del solo giorno/agenda selezionato. Per aprire, togliere la spunta e aggiungere almeno un intervallo. Eccezioni per data gestite separatamente.
- Vincolo database contro sovrapposizioni tra appuntamenti e blocchi dello stesso barbiere, con lock per richieste concorrenti.
- Nome e prezzo del servizio prenotato rimangono nello storico anche dopo modifiche al catalogo.
- Nuova prenotazione manuale staff: nome e cognome obbligatori, telefono facoltativo, nessuna email obbligatoria. Possibili clienti ospiti senza account.
- Telefono corrispondente a un solo profilo disponibile: collegamento automatico all’account tramite client_id, visibile in Le mie prenotazioni. Confronto canonico del numero completo, con prefissi +39/0039 e numeri locali italiani. Numeri duplicati richiedono correzione o campo vuoto per ospite. Nessuna nuova utenza o associazione retroattiva.
- Salvataggio manuale riuscito: ritorno automatico ad Appuntamenti sulla stessa agenda e data prenotata. Le mie prenotazioni ricarica all’apertura, al ritorno in primo piano e ogni 30 secondi mentre visibile.
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

- Manutenzione giornaliera alle 03:15 UTC; soglie numeriche modificabili e salvate tramite save_maintenance_settings, senza modificare la politica iscrizioni ora gestita in Configurazione.
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

### 17 ottobre 2026 — Diagnosi apertura prenotazioni

Verifica in sola lettura: prenotazioni disabilitate, termini pubblicati e preavviso cancellazione di 12 ore presenti. Il barbiere attivo ha un servizio associato ma nessun turno in working_hours: il controllo configurazione impedisce l'apertura perché non esiste un'agenda attiva con servizio e orari. Le 6 righe orario complessive appartengono ad altre agende e non soddisfano il requisito per quella attuale. Occorre impostare gli orari reali del barbiere in Orari di lavoro, poi salvare Apri le prenotazioni online in Configurazione admin. Nessun orario inventato e nessuna impostazione operativa modificata.

### 17 ottobre 2026 — Spunta Chiuso negli orari

Aggiunta checkbox Chiuso nella settimana abituale, con selezione giorno, campi orario disabilitati quando chiuso e salvataggio esplicito. Riepilogo visibile da lunedì a domenica, compresi i giorni senza intervalli indicati come Chiuso. Salvare una chiusura rimuove solo gli intervalli del giorno e del barbiere selezionati, tramite gli stessi permessi RLS esistenti; nessuna modifica allo schema o agli orari reali durante lo sviluppo. Migliorata gestione errori rimozione intervalli. Anche le eccezioni con Chiuso disabilitano gli orari, richiesti solo per aperture. Verifiche completate: TypeScript, build, test e pubblicazione GitHub Pages riusciti nella [CI 39019273425](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39019273425). Nessuna prova autenticata del nuovo form su dispositivo fisico.

### 17 ottobre 2026 — Posizione della spunta Chiuso

Spostata la checkbox Chiuso dopo i campi Apertura/Chiusura e immediatamente sopra il pulsante Aggiungi intervallo (Salva giorno di chiusura quando selezionata), come richiesto. Solo ordine visivo, comportamento e dati invariati. Verificati ordine nel sorgente, build, test e pubblicazione nella [CI 39019531762](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39019531762), completata con successo.

### 17 ottobre 2026 — Modalità iscrizione dal profilo barbiere

Aggiunta sezione Iscrizione nuovi clienti nel profilo staff autorizzato, con Accetta automaticamente i nuovi utenti oppure Richiedi approvazione e pulsante Salva modalità di iscrizione. Unica impostazione condivisa con Manutenzione; modifica applicata solo alle registrazioni future, verifica email e stati già esistenti invariati. Estesa la RPC set_registration_policy ai soli admin verificati e barbieri verificati con agenda attiva associata, senza concedere accesso alle altre impostazioni. Migrazione remota 20261017090241. Test SQL con rollback riusciti: cliente, barbiere non verificato/inattivo/non associato esclusi; staff autorizzato ammesso; flag nullo respinto; manutenzione e altre impostazioni protette; nuovi utenti automatici e vecchi pendenti preservati. Rerun client_approval.sql riuscito, nessun account o invio reale di test. Advisor senza nuovi rilievi: INFO tabelle private volutamente senza accesso diretto e WARN preesistente protezione password compromesse disabilitata. [Documentazione del rilievo preesistente](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). TypeScript, build, test e pubblicazione GitHub Pages riusciti nella [CI 39019691597](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39019691597). Impostazione live mantenuta su approvazione richiesta; nessun test autenticato del nuovo form su dispositivo fisico.

### 17 ottobre 2026 — Prenotazioni manuali collegate e ritorno all’agenda

Aggiornata RPC book_guest_appointment: telefono facoltativo confrontato sul server con i profili non in eliminazione e account non bloccati; corrispondenza univoca collega client_id, numero vuoto/sconosciuto mantiene ospite, duplicati respinti senza scelta arbitraria. Normalizzazione completa (spazi, punteggiatura, +39/0039; numero locale senza prefisso considerato italiano); nessun confronto sui soli suffissi. Lock cliente prima del barbiere, limite 5 e trigger approvazione conservati. Migrazione 20261017113822. Nessun collegamento retroattivo di appuntamenti già salvati. Dopo inserimento riuscito, nuova schermata Appuntamenti con barbiere e data appena prenotati; aggiornamento periodico della lista del cliente. Test SQL manual_booking_phone.sql e barber_workflows.sql superati in transazioni con rollback: collegamento/RLS proprietario, isolamento da altri clienti, ospiti vuoti/sconosciuti, duplicati, autorizzazione staff, approvazione e limite cinque; nessun dato reale di test conservato. Advisor senza nuovi rilievi rispetto al controllo precedente. TypeScript, build, test frontend e pubblicazione GitHub Pages completati con successo nella [CI 39029578128](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39029578128). Nessuna prova del flusso autenticato su dispositivo fisico.

### 17 ottobre 2026 — Una sola spunta per accettazione clienti

Sostituiti i due radio del profilo barbiere con una sola checkbox Accetta i nuovi clienti senza approvazione, con indicazione attiva=automatica/disattiva=approvazione. Componente condiviso tra profilo barbiere e Configurazione admin, posizionato prima di Apri le prenotazioni online. Rimossa l’impostazione da Manutenzione e dal profilo admin; Salva manutenzione ora usa la RPC delle sole soglie, evitando di sovrascrivere una politica aggiornata altrove. Configurazione salva il flag insieme agli altri campi del form in un unico aggiornamento; profilo barbiere mantiene la RPC con permessi limitati. Nessun cambio schema o valore live durante l’intervento. Verificati nel sorgente checkbox unica, inversione corretta del flag, ordine nel form admin e assenza del campo in Manutenzione. TypeScript, build, test e pubblicazione GitHub Pages riusciti nella [CI 39030058198](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39030058198). Nessuna verifica autenticata su dispositivo fisico.

### 17 ottobre 2026 — Rimosso testo sotto il limite cancellazione

Rimosso da Configurazione il paragrafo “Lascia vuoto finché la regola non è decisa. Zero permette di cancellare fino all’inizio.” su richiesta del titolare. Modifica del solo testo: campo e regola di cancellazione invariati. Controllata la rimozione nel sorgente; build, test e pubblicazione riusciti nella [CI 39030278941](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39030278941).

### 17 ottobre 2026 — Area Cliente per l’admin

Aggiunto in fondo ai comandi admin il tasto Cliente, con schermata dedicata Prenota, Servizi e prezzi, Le mie prenotazioni e Informazioni. Riutilizzati i flussi cliente esistenti con lo stesso account; nessuna modifica a ruoli, schema o impostazioni operative. Navigazione indietro dalle funzioni personali al menu Cliente. Test SQL admin_customer_booking.sql superato con rollback: prenotazione personale dell’admin correttamente associata al suo account e visibile nella query delle proprie prenotazioni, ruolo Admin preservato. Nessun appuntamento reale creato per il test. TypeScript, build, test e pubblicazione GitHub Pages riusciti nella [CI 39031007103](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39031007103). Nessuna prova autenticata del nuovo menu su dispositivo fisico.

### 17 ottobre 2026 — Descrizione servizi tramite icona informativa

Rimossa la descrizione dalla riga della durata nel catalogo cliente. Aggiunta icona ⓘ accanto al prezzo, dello stesso colore accento giallo dell’app, con area tocco 44px e nome accessibile del servizio. Apre una schermata dedicata alla descrizione e permette di tornare al catalogo; testo multilinea preservato e fallback per descrizione vuota. Catalogo condiviso anche dall’area Cliente admin. Nessuna modifica ai dati del catalogo o alle prenotazioni. TypeScript, build, test e pubblicazione riusciti nella [CI 39031458281](https://github.com/MISCIANDOSKY/BarberCut/actions/runs/39031458281). Verificati nel browser pubblico catalogo con durata senza descrizione inline, icona gialla accanto al prezzo, apertura descrizione e ritorno al catalogo.

### 17 ottobre 2026 — Dopo prenotazione cliente apri Le mie prenotazioni

Il callback di successo del flusso Prenota ora apre direttamente Le mie prenotazioni, conferma il salvataggio e aggiorna l’elenco. Vale anche per prenotazioni personali dell’admin; prenotazioni manuali staff e percorsi di errore invariati. Nessuna modifica al database e nessuna prenotazione reale creata per il test. Controllata la chiamata solo dopo salvataggio riuscito; build, test e pubblicazione da confermare in CI.
