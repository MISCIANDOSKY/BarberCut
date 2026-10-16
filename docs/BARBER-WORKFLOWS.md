# Gestione barbieri e prenotazioni manuali

Il collegamento di un account attivo a un barbiere assegna automaticamente il ruolo Barbiere. Un account già Admin mantiene quel ruolo. Gli account già associati ad agende attive sono stati allineati dalla migration.

Le prenotazioni manuali richiedono nome e cognome del cliente. Il telefono è facoltativo; non occorrono email né account cliente. I dati ospite sono memorizzati nell'appuntamento e restano visibili solo al barbiere autorizzato e all'admin. Non è creata alcuna rubrica clienti o utenza Auth.

Il barbiere può operare soltanto sulla propria agenda. L'admin mantiene la gestione delle agende del negozio. La verifica email riservata rimane obbligatoria per accedere alle operazioni staff.

Ogni barbiere può aggiungere, modificare ed eliminare i propri servizi. Se un servizio è condiviso, la modifica crea una versione associata soltanto al barbiere che la effettua, senza cambiare nome, prezzo o durata per gli altri. Gli appuntamenti già presenti conservano nome e prezzo prenotati.

L'admin dispone sia di Disattiva sia di Elimina per servizi e barbieri. Elimina rimuove la voce dagli elenchi tramite archiviazione; i riferimenti degli appuntamenti sono conservati. Non è possibile eliminare un barbiere con appuntamenti futuri o in corso: occorre prima liberarli o spostarli.

## Verifica

Il test SQL supabase/tests/barber_workflows.sql è stato eseguito sul progetto con fixture racchiuse in una transazione e rollback. Verifica ruoli automatici, conservazione ruolo Admin, nome/cognome obbligatori, telefono facoltativo, nessuna creazione di account ospite, blocco accesso ad altre agende, modifica/cancellazione ospiti, isolamento dei servizi condivisi, creazione/rimozione servizi e cancellazioni admin con storico conservato.
