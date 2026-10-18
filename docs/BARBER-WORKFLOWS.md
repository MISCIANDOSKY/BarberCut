# Gestione barbieri e prenotazioni manuali

Il collegamento di un account attivo a un barbiere assegna automaticamente il ruolo Barbiere. Un account già Admin o Barbiere Admin mantiene quel ruolo. Gli account già associati ad agende attive sono stati allineati dalla migration.

Le prenotazioni manuali richiedono nome e cognome del cliente. Il telefono è facoltativo; non occorrono email né account cliente. Se il telefono corrisponde a un unico account non bloccato e non in eliminazione, il server collega l'appuntamento a quell'account: compare così anche in Le mie prenotazioni. Sono riconosciuti spazi, punteggiatura e prefissi +39/0039; i numeri locali senza prefisso sono considerati italiani. Non viene usato un confronto parziale sui suffissi. Con più profili corrispondenti l'inserimento richiede di correggere il numero o lasciarlo vuoto per un ospite. Senza corrispondenza rimane una prenotazione ospite. I dati restano visibili solo a staff autorizzato e, se collegato, al titolare dell'appuntamento. Non è creata alcuna rubrica clienti o utenza Auth.

Il barbiere può operare soltanto sulla propria agenda. L'admin mantiene la gestione delle agende del negozio. La verifica email riservata rimane obbligatoria per accedere alle operazioni staff.

L’admin assegna il ruolo Barbiere Admin da Utenti. Il Barbiere Admin può aggiungere, modificare ed eliminare i servizi della propria agenda; il Barbiere normale può soltanto disattivarli e riattivarli per sé. Lo stato attivo dell’associazione è distinto dallo stato globale del servizio: disattivare per sé non cambia la disponibilità degli altri. Se un servizio è condiviso, la modifica crea una versione associata soltanto al barbiere che la effettua, senza cambiare nome, prezzo o durata per gli altri. Gli appuntamenti già presenti conservano nome e prezzo prenotati.

L'admin dispone sia di Disattiva sia di Elimina per servizi e barbieri. Elimina rimuove la voce dagli elenchi tramite archiviazione; i riferimenti degli appuntamenti sono conservati. Non è possibile eliminare un barbiere con appuntamenti futuri o in corso: occorre prima liberarli o spostarli.

## Verifica

Il test SQL supabase/tests/barber_workflows.sql è stato eseguito sul progetto con fixture racchiuse in una transazione e rollback. Verifica ruoli automatici, conservazione ruolo Admin, nome/cognome obbligatori, telefono facoltativo, nessuna creazione di account ospite, blocco accesso ad altre agende, modifica/cancellazione ospiti, isolamento dei servizi condivisi, creazione/rimozione servizi e cancellazioni admin con storico conservato.

Dopo un inserimento manuale riuscito, il barbiere viene portato ad Appuntamenti nella stessa agenda e data prenotata. Le mie prenotazioni si aggiorna quando viene aperto, al ritorno in primo piano e ogni 30 secondi mentre visibile. I controlli di approvazione cliente e limite cinque appuntamenti futuri restano applicati agli account collegati. Il nuovo comportamento si applica agli inserimenti successivi: nessuna associazione retroattiva è eseguita.

Il test supabase/tests/manual_booking_phone.sql verifica normalizzazione, corrispondenze uniche e duplicate, casi ospite, visibilità RLS del cliente, isolamento degli altri clienti, autorizzazioni, approvazione e limite cinque con rollback.

## Appuntamenti manuali nei giorni non lavorativi

Nel flusso Nuova prenotazione, entrambi i ruoli barbiere possono selezionare orari nell’intera giornata locale, dalle 00:00 fino a terminare entro le 00:00 del giorno successivo, anche nei giorni lavorativi. Per un intervallo fuori dalla disponibilità abituale, compresi festivi, chiusure e ferie, compare “In questo giorno o in questa fascia oraria risulti chiuso. Sei sicuro di voler inserire un appuntamento?” con No e Sì. No non salva; Sì invia la conferma esplicita al server. Le prenotazioni personali dei clienti e dell’admin nell’area Cliente continuano a usare la disponibilità normale.

Le nuove RPC get_manual_booking_slots e book_manual_appointment verificano sessione staff e agenda autorizzata. Il server richiede p_confirm_closed=true per ogni intervallo fuori dalla disponibilità ordinaria; la vecchia book_guest_appointment passa false e non aggira il requisito. Restano esclusi intervalli sovrapposti ad appuntamenti o blocchi orari, il passato e le date oltre tre mesi. Restano attivi collegamento telefono, approvazione cliente e limite cinque. Nessuna modifica agli orari della barberia o apertura della disponibilità pubblica. Il test manual_closed_days.sql copre conferma obbligatoria, festività, ferie, chiusure settimanali, normali aperture, conflitti, blocchi, permessi e orizzonte temporale con rollback.

Il test barber_admin_permissions.sql verifica limiti dei due ruoli, assegnazione admin, revoca dei permessi dopo declassamento, disattivazione per agenda, modifica isolata dei servizi condivisi, disponibilità 00:00–24:00 e conferma server fuori orario. Il Barbiere Admin può modificare indirizzo e politica di iscrizione dal Profilo; non ottiene accesso all’amministrazione globale.

## Assumi Barbiere dalla home

Solo il Barbiere Admin verificato con agenda attiva vede il pulsante Assumi Barbiere nella home, subito dopo Notifiche e prima di Profilo. Il pulsante apre direttamente il form a schermata completa, con freccia indietro. Apre una schermata dedicata con l’avviso: “Prima di procedere, assicurati che il nuovo collaboratore sia già registrato a BarberCut come cliente. Inserisci l’email e il numero di telefono presenti nel suo profilo.” Nessun riferimento alla conferma email in questo avviso.

Il primo passaggio confronta l’email Auth (ignorando maiuscole e spazi esterni) e il telefono del profilo, normalizzato sul numero completo con la logica delle prenotazioni. Devono appartenere allo stesso account Cliente disponibile, non bloccato, non in eliminazione e non già associato a un’agenda non eliminata. Non vengono restituiti nome, email o identificativo del candidato. Una risposta positiva sblocca il campo Nome da mostrare in agenda.

Conferma assunzione ricontrolla la coppia email/telefono sul server dopo lock dei record: nessun identificativo o permesso viene accettato dal browser. Crea una sola agenda attiva, assegna automaticamente il ruolo Barbiere e associa i servizi attivi con i trigger esistenti. Il nuovo collaboratore può soltanto disattivare/riattivare i propri servizi, non modificare o eliminare il catalogo, assegnarsi Barbiere Admin o assumere altri collaboratori. Solo l’admin globale assegna Barbiere Admin da Utenti. L’accesso staff continua a richiedere la verifica email della sessione; non viene creata alcuna utenza Auth nuova e nessuna email di invito viene inviata.

L’admin globale può continuare ad aggiungere barbieri dalla propria sezione: i nuovi account Cliente collegati ricevono automaticamente il ruolo Barbiere. I ruoli Admin e Barbiere Admin già assegnati non vengono implicitamente declassati associando/modificando l’agenda.

Test supabase/tests/barber_hiring.sql con rollback: corrispondenza coppia e formati telefono, mismatch incrociato, assenza account, account già staff/bloccati, controllo ripetuto dopo modifica telefono, ruolo automatico, servizi eleggibili, niente duplicati o nuova utenza Auth, diniego a clienti, barbieri normali, staff non verificato/non associato e inserimento diretto di agende.
