# Verifica eseguita online

- Build TypeScript/Vite e test PWA eseguiti su GitHub Actions.
- Disponibilità SQL: durate 15/30/45 minuti, blocchi parziali, confini adiacenti, chiusura giornata, festività, Pasquetta, apertura straordinaria, limite tre mesi.
- RLS e limiti SQL: massimo cinque appuntamenti, isolamento profili e prenotazioni, impossibilità di promuovere il proprio ruolo, rifiuto cancellazione altrui e pubblicazione termini da cliente, rifiuto inserimento diretto appuntamenti da cliente.
- Concorrenza effettiva: due transazioni parallele sullo stesso intervallo; una inserita e una respinta dall’exclusion constraint, conteggio finale uno. Fixture temporanee eliminate.
- Fixture SQL degli altri test racchiuse in transazione con rollback: nessun dato fittizio rimasto nel catalogo.
- Home e flusso pubblico verificati nel browser a larghezza desktop e 390px.
- Login reale non eseguito: nessuna password dell’utente disponibile. Nessuna email di prova inviata.
- Test su dispositivi fisici iPhone/Android ancora da svolgere.

## Configurazioni residue del titolare

Il progetto usa ancora il mittente email integrato Supabase. Per clienti esterni e codici OTP nei modelli serve configurare SMTP esterno e relativo modello email; il link monouso predefinito è supportato nello stesso browser.

Configurare catalogo, prezzi, barbieri, orari, associazioni e termini approvati. Aprire quindi le prenotazioni dalla configurazione admin. Le regole mancanti non sono state sostituite con prezzi, orari o testi legali inventati.

Le notifiche 24h/1h sono interne alla PWA; Web Push ed email di promemoria non sono attivati. La pulizia automatica di utenti/appuntamenti è disattivata. L’export JSON non è un dump completo con Auth.
