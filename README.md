# BarberCut

PWA React + TypeScript pubblicata con GitHub Pages, con Supabase come backend centrale. Nessun database locale sul dispositivo; la cache contiene esclusivamente la shell dell'app.

## Operatività

La CI esegue installazione con lockfile, controllo TypeScript, build, test PWA e pubblicazione. Il sito è raggiungibile dall'URL restituito dal deployment GitHub Pages. Il percorso previsto è /BarberCut/.

Le prenotazioni inizialmente sono chiuse: il titolare configura servizi, barbieri, associazioni, orari, termini approvati e regola di cancellazione prima di aprirle.

## Sicurezza

RLS su tutte le tabelle pubbliche. Ruoli in tabella non modificabile dal cliente. Password + verifica email per barbiere/admin: una Edge Function verifica entrambi i token Supabase e abilita esclusivamente la sessione verificata per 8 ore. La service_role rimane solo nell'ambiente Supabase. Nessuna OTP applicativa in chiaro.

Prenotazioni tramite RPC: lock per cliente e barbiere, controllo massimo 5 appuntamenti futuri e 3 mesi, intervallo completo del servizio e exclusion constraint contro sovrapposizioni tra appuntamenti e blocchi. Disponibilità in Europe/Rome, festività nazionali e Pasquetta, eccezioni prioritarie rispetto a orari settimanali. Le chiusure prevalgono sulle aperture per la stessa data.

## Configurazione Supabase Auth

In Authentication > URL Configuration impostare Site URL e Redirect URL a https://misciandosky.github.io/BarberCut/. Nel modello email Magic Link includere {{ .Token }} per consentire l'inserimento del codice OTP; il link email nello stesso browser è supportato come alternativa. Configurare un SMTP esterno per la consegna in produzione: il mittente integrato ha limiti e restrizioni. Non inserire credenziali nel repository.

Il primo admin è stato associato all'account indicato dal titolare. Per il barbiere associare un account registrato e impostarne il ruolo dall'area admin.

## Limiti espliciti

Non sono attivate cancellazioni automatiche di dati o account. Eliminazione account, retention, push ed email di promemoria richiedono configurazione e approvazione delle regole. I promemoria interni 24h e 1h sono attivi tramite pg_cron e deduplicati per appuntamento e orario. L'export JSON admin è un'esportazione applicativa e non sostituisce un dump PostgreSQL completo con Auth. Non sono stati svolti test fisici su Safari iPhone o Chrome Android.

## Sorgenti

- src/components: componenti accessibili, installazione e aggiornamenti PWA
- src/features: autenticazione, prenotazione, account, agenda e amministrazione
- supabase/migrations: schema versionato
- supabase/functions: verifica email riservata
- scripts: icone PNG e service worker generati in CI

Le migrations 0001 e 0002 sono state applicate al progetto Supabase esistente. La vecchia tabella vuota bookings è stata preservata nello schema private senza accesso ai client.
