# Manutenzione automatica

L’admin può modificare le soglie numeriche in Manutenzione e premere Salva manutenzione. Valori iniziali: 120 giorni per account inattivi, 40 giorni per appuntamenti passati. Le due operazioni sono attive e possono essere sospese separatamente.

Il job Supabase Cron `barbercut-daily-maintenance` esegue `private.run_daily_maintenance()` ogni giorno alle 03:15 UTC (05:15 in Italia con ora legale, 04:15 con ora solare). La funzione è eseguibile solo dal proprietario database, non da anon, authenticated o service_role. Un lock evita esecuzioni simultanee.

Sono disattivati solo account con ruolo client, senza associazione a un barbiere né appuntamenti confermati futuri. L’attività è il massimo tra creazione, ultimo accesso, sessioni Auth e un timestamp privato aggiornato dal client ogni 15 minuti quando visibile, al ritorno nella finestra e al caricamento dei dati. La disattivazione conserva profilo e storico, imposta il blocco Auth e revoca le sessioni. I ban già attivi non vengono modificati. L’admin può riattivare gli account disattivati automaticamente da Manutenzione; l’inattività riparte da quel momento.

Sono eliminati definitivamente soltanto record calendar_entries di tipo appointment con end_at strettamente anteriore alla mezzanotte italiana del giorno di oggi meno la soglia. Tutti gli stati appuntamento sono inclusi; blocchi agenda, appuntamenti recenti, al confine e futuri restano. I dati derivati delle notifiche non sono eliminati da questa operazione.

Impostazioni, attività, account disattivati e risultati esecuzioni risiedono nello schema privato con RLS e accesso diretto revocato ai client. Le RPC admin controllano ruolo e sessione staff verificata. Nessuna chiave privilegiata è usata nel frontend. La tabella esecuzioni registra soltanto conteggi e soglie; lo stato della manutenzione mostra l’ultima esecuzione.

Test SQL in supabase/tests/daily_maintenance.sql: fixture create in transazione e sempre annullate, account inattivo/attivo/staff/futuro, riattivazione, protezione soglia calendario, autorizzazione RPC e limiti numerici. L’attivazione non ha eseguito una pulizia immediata dei dati reali; il primo passaggio è quello programmato.
