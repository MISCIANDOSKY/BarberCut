# Promemoria appuntamenti in app

Sono generati due promemoria per gli appuntamenti confermati associati a un account:
- 24 ore prima.
- 1 ora prima.

Il titolo distingue il promemoria giornaliero da quello orario. Il messaggio è:
“Ricordati del tuo appuntamento! Hai prenotato [servizio] per il [GG/MM/AAAA] alle [HH:MM]. Ti aspettiamo in barberia.”

Data e ora sono nel fuso Europe/Rome; servizio e prezzo prenotati restano quelli dello storico dell'appuntamento.

## Esecuzione e visualizzazione

Il cron barbercut-appointment-reminders esegue private.appointment_reminders() ogni 5 minuti. La generazione avviene al primo ciclo dopo la soglia; la finestra di recupero giornaliera resta 23–24 ore prima e quella oraria nell'ultima ora precedente l'inizio. Nessun invio dopo l'inizio.

La chiave univoca contiene appuntamento, tipo 24h/1h e orario di inizio: chiamate ripetute non duplicano il promemoria. Gli appuntamenti annullati, i blocchi e gli ospiti senza account sono esclusi; le prenotazioni manuali collegate via telefono possono ricevere il promemoria come le altre.

Le notifiche sono salvate nel database e compaiono nell'area Notifiche dell'account destinatario. App e badge si aggiornano ogni 30 secondi mentre l'app è visibile, al focus e al ritorno online. Con l'app chiusa le notifiche restano consultabili al successivo accesso: non sono notifiche push o email.

La funzione cron resta eseguibile solo dal server. RLS limita la visibilità e la marcatura come letta al destinatario, oltre ai privilegi amministrativi previsti.

## Verifiche

supabase/tests/appointment_reminders.sql verifica con rollback soglie 24h/1h, testo italiano, destinatario, deduplicazione, esclusioni, lettura del proprietario, isolamento di un altro cliente e cron attivo. Nessun appuntamento o notifica di prova viene conservato.
