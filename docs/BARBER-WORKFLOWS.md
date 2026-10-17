# Gestione barbieri e prenotazioni manuali

Il collegamento di un account attivo a un barbiere assegna automaticamente il ruolo Barbiere. Un account già Admin mantiene quel ruolo. Gli account già associati ad agende attive sono stati allineati dalla migration.

Le prenotazioni manuali richiedono nome e cognome del cliente. Il telefono è facoltativo; non occorrono email né account cliente. Se il telefono corrisponde a un unico account non bloccato e non in eliminazione, il server collega l'appuntamento a quell'account: compare così anche in Le mie prenotazioni. Sono riconosciuti spazi, punteggiatura e prefissi +39/0039; i numeri locali senza prefisso sono considerati italiani. Non viene usato un confronto parziale sui suffissi. Con più profili corrispondenti l'inserimento richiede di correggere il numero o lasciarlo vuoto per un ospite. Senza corrispondenza rimane una prenotazione ospite. I dati restano visibili solo a staff autorizzato e, se collegato, al titolare dell'appuntamento. Non è creata alcuna rubrica clienti o utenza Auth.

Il barbiere può operare soltanto sulla propria agenda. L'admin mantiene la gestione delle agende del negozio. La verifica email riservata rimane obbligatoria per accedere alle operazioni staff.

Ogni barbiere può aggiungere, modificare ed eliminare i propri servizi. Se un servizio è condiviso, la modifica crea una versione associata soltanto al barbiere che la effettua, senza cambiare nome, prezzo o durata per gli altri. Gli appuntamenti già presenti conservano nome e prezzo prenotati.

L'admin dispone sia di Disattiva sia di Elimina per servizi e barbieri. Elimina rimuove la voce dagli elenchi tramite archiviazione; i riferimenti degli appuntamenti sono conservati. Non è possibile eliminare un barbiere con appuntamenti futuri o in corso: occorre prima liberarli o spostarli.

## Verifica

Il test SQL supabase/tests/barber_workflows.sql è stato eseguito sul progetto con fixture racchiuse in una transazione e rollback. Verifica ruoli automatici, conservazione ruolo Admin, nome/cognome obbligatori, telefono facoltativo, nessuna creazione di account ospite, blocco accesso ad altre agende, modifica/cancellazione ospiti, isolamento dei servizi condivisi, creazione/rimozione servizi e cancellazioni admin con storico conservato.

Dopo un inserimento manuale riuscito, il barbiere viene portato ad Appuntamenti nella stessa agenda e data prenotata. Le mie prenotazioni si aggiorna quando viene aperto, al ritorno in primo piano e ogni 30 secondi mentre visibile. I controlli di approvazione cliente e limite cinque appuntamenti futuri restano applicati agli account collegati. Il nuovo comportamento si applica agli inserimenti successivi: nessuna associazione retroattiva è eseguita.

Il test supabase/tests/manual_booking_phone.sql verifica normalizzazione, corrispondenze uniche e duplicate, casi ospite, visibilità RLS del cliente, isolamento degli altri clienti, autorizzazioni, approvazione e limite cinque con rollback.

## Appuntamenti manuali nei giorni non lavorativi

Solo nel flusso Nuova prenotazione staff, festivi, chiusure settimanali ed eccezioni di chiusura/ferie consentono di selezionare un orario sul giorno completo. Prima del salvataggio compare “Questo giorno non devi lavorare. Sei sicuro di inserire un appuntamento?” con No e Sì. No non salva; Sì invia la conferma esplicita al server. I giorni lavorativi mantengono gli orari abituali. Le prenotazioni personali dei clienti e dell’admin nell’area Cliente continuano a usare la disponibilità normale.

Le nuove RPC get_manual_booking_slots e book_manual_appointment verificano sessione staff e agenda autorizzata. Il server richiede p_confirm_closed=true per i giorni non lavorativi; la vecchia book_guest_appointment passa false e non aggira il requisito. Restano esclusi intervalli sovrapposti ad appuntamenti o blocchi orari, il passato e le date oltre tre mesi. Restano attivi collegamento telefono, approvazione cliente e limite cinque. Nessuna modifica agli orari della barberia o apertura della disponibilità pubblica. Il test manual_closed_days.sql copre conferma obbligatoria, festività, ferie, chiusure settimanali, normali aperture, conflitti, blocchi, permessi e orizzonte temporale con rollback.
