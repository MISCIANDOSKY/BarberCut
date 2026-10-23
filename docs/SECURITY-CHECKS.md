# Controllo sicurezza settimanale

Il controllo gira sui server GitHub, anche con il PC spento, ogni venerdì alle 09:00 nel fuso Europe/Rome. GitHub può ritardare l’avvio. Non modifica dati, account, credenziali o dipendenze dell’app.

## Dove leggere il risultato

Aprire [Controllo sicurezza settimanale](https://github.com/MISCIANDOSKY/BarberUp/actions/workflows/security-audit.yml), scegliere l’esecuzione e leggere il riepilogo. Il job diventa rosso quando rileva problemi oppure non riesce a completare un controllo. Un job verde significa soltanto che i controlli previsti non hanno rilevato anomalie.

Gli eventuali avvisi email dipendono dalle [preferenze personali GitHub Actions](https://github.com/settings/notifications); la configurazione non le modifica. Il risultato non arriva automaticamente nella chat Codex. La precedente automazione locale è sospesa.

Per avviare una prova: Actions → Controllo sicurezza settimanale → Run workflow → main. Non serve un PC sempre acceso. Nei repository pubblici GitHub può disabilitare le pianificazioni dopo 60 giorni senza attività: in tal caso occorre riabilitarle da Actions.

## Cosa verifica

- Gitleaks 8.30.1 su tutta la cronologia Git raggiungibile. Binario ufficiale verificato tramite SHA-256; esclusa soltanto l’esatta chiave Supabase pubblicabile già verificata, non i prefissi o interi file.
- npm audit del lockfile, comprese dipendenze di sviluppo. Ogni vulnerabilità segnalata causa un avviso.
- Catalogo Supabase: RLS su tabelle public/private, accesso diretto dei client a tabelle private, funzioni public privilegiate richiamabili dai client, search_path esplicito, viste invoker e policy palesemente permissive su tabelle sensibili.
- Endpoint audit che rifiuta richieste anonime e JWT falsi.

Non verifica ogni scenario dei ruoli né tutte le impostazioni Auth, MFA, SMTP, rate limit, Storage o gli advisor completi. Serve anche una revisione periodica più approfondita. Non è una certificazione di sicurezza.

## Autenticazione e riservatezza

GitHub ottiene un token OIDC temporaneo: nessuna nuova chiave amministrativa persistente nei Secrets. La Edge Function weekly-security-audit verifica firma, issuer, audience, scadenza, repository/owner con ID immutabili, ramo main, percorso workflow ed evento. Il gateway verify_jwt è disattivato esclusivamente per questa funzione, che verifica autonomamente l’identità GitHub. La RPC di catalogo è accessibile soltanto a service_role e legge solo metadati, non righe cliente. La risposta ammette solo i contatori previsti.

Nei log non vengono stampati token, risultati grezzi dello scanner o dati dei clienti. Eventuali identificatori tecnici di posizione e codici advisory sono filtrati; i report temporanei dello scanner vengono rimossi e non caricati come artifact.

## Prima esecuzione verificata — 23 ottobre 2026

[Esecuzione 39920204614](https://github.com/MISCIANDOSKY/BarberUp/actions/runs/39920204614): zero potenziali segreti dopo revisione della chiave pubblicabile, sei controlli Supabase senza rilievi su 33 tabelle; un pacchetto di sviluppo/build segnalato high (Vite). Il job è rosso per questo rilievo reale, non per un malfunzionamento del controllo. Nessuna correzione automatica delle dipendenze eseguita.

## Aggiornamento verificato — 23 ottobre 2026

Vite aggiornato a 8.3.5 e lockfile rigenerato dal workflow remoto. Build, test e pubblicazione riusciti nella pipeline 39989753337. [Nuovo controllo 39989861964](https://github.com/MISCIANDOSKY/BarberUp/actions/runs/39989861964) completato con successo: zero vulnerabilità npm, zero potenziali segreti e nessun rilievo nei sei controlli aggregati Supabase su 33 tabelle. La precedente segnalazione Vite è risolta; restano validi i limiti del controllo descritti sopra.

Il controllo parte anche sulle normali push che cambiano package-lock.json; i commit generati con GITHUB_TOKEN non attivano altri workflow GitHub, quindi in questi casi usare Run workflow oppure attendere la verifica settimanale.
