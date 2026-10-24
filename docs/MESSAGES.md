# Messaggi nella PWA

Aprire **Profilo → Messaggi**, sopra Notifiche.

## Chi può scrivere

- Admin, Barbiere Admin e Barbiere con agenda attiva e accesso staff verificato possono iniziare una conversazione con un cliente registrato della barberia.
- Admin e barbieri (normali o Admin) possono scriversi in entrambe le direzioni, iniziando la conversazione da ciascuna parte. Questi scambi non scadono a mezzanotte e riutilizzano una sola conversazione per coppia.
- Il cliente non può iniziare. Può rispondere soltanto nel giorno italiano dell’ultimo messaggio ricevuto da quel referente, fino alla mezzanotte Europe/Rome. Un nuovo messaggio dello staff riapre le risposte. La regola è controllata sul server e comprende l’ora legale.
- Ogni conversazione è privata tra il cliente e il singolo admin/barbiere che l’ha avviata. Gli altri barbieri non possono leggerla. Il ruolo Barberia non accede ai messaggi.

## Da dove inviare

- Da Messaggi: **Nuovo messaggio** e ricerca del destinatario per nome, cognome o telefono (almeno due caratteri).
- Da Utenti: **Invia messaggio** sotto lo stato del cliente; nella gestione ruoli Admin anche sotto i ruoli Cliente, Barbiere e Barbiere Admin.
- Dai dettagli di un appuntamento associato a un cliente registrato: **Invia messaggio in app**, sotto Chiama. Per un ospite senza account non si inviano messaggi.

Il pulsante invia un messaggio interno: non viene usata la rete SMS telefonica e non vengono addebitati SMS. Solo testo, nessun allegato; massimo 2.000 caratteri e 20 messaggi al minuto per mittente.

## Notifiche e privacy

Ogni nuovo messaggio o risposta crea un avviso in app e, se abilitate e autorizzate sul dispositivo, una push. Da **Profilo → Notifiche** l’interruttore push comprende promemoria e messaggi. Spegnerlo lascia disponibili i messaggi e gli avvisi interni. La spunta separata **Notifiche push dei messaggi** permette di disattivare solo le push delle chat, senza modificare i promemoria appuntamento o le sottoscrizioni del dispositivo. La scelta vale per l’account su tutti i dispositivi; resta memorizzata anche spegnendo e riaccendendo l’interruttore generale. Per ricevere le push dei messaggi devono essere attivi entrambi gli interruttori e il permesso del dispositivo. Disattivare la spunta annulla le consegne messaggi ancora in attesa. I default dei barbieri rimangono quelli già configurati, con push inizialmente spente.

Il dispatcher controlla la coda ogni minuto. Il testo della conversazione non compare nella push: un avviso generico apre la casella Messaggi. Messaggi già letti o avvisi eliminati vengono esclusi dalla consegna; tentativi/scadenza sono limitati. La ricezione effettiva dipende dal permesso del dispositivo e dal servizio push. Su iPhone serve la PWA aggiunta alla schermata Home con iOS 16.4 o successivo.

Messaggi e conversazioni sono in tabelle private con RLS, senza accesso diretto client. API controllano sessione reale, termini, ruolo, partecipanti e finestra di risposta. La cancellazione del profilo elimina in cascata le sue conversazioni e i messaggi associati.

## Verifiche

- Test SQL con rollback: supabase/tests/direct_messages.sql, compresi avvio e risposta Admin ↔ entrambi i ruoli barbiere, riuso della conversazione, ricerca, isolamento e vincoli cliente invariati.
- Test frontend/worker e build/pubblicazione: pipeline 39993081163.
- Prova UI con account temporanei poi rimossi: invio Admin, risposta cliente, chiusura risposte, profilo, collegamento push e layout fino a 320 pixel. Nessun invio a clienti reali. Ricezione push su telefono fisico non verificata.

## Rimozione e conservazione

Ogni chat ha un cestino: rimuove tutti i messaggi già presenti solo dalla vista dell’utente che lo preme. Gli altri partecipanti mantengono la propria copia visibile. Il server conserva i messaggi fino alla scadenza. Un nuovo messaggio fa ricomparire la chat senza ripristinare i precedenti messaggi rimossi. La scelta vale su tutti i dispositivi dello stesso account.

Solo Admin, Barbiere e Barbiere Admin hanno anche **Elimina tutto**, in alto nella casella Messaggi. Il cliente può eliminare soltanto singole chat. Ogni comando chiede conferma nel dialog integrato nella PWA e non avvia alcuna cancellazione del contenuto sul server.

La manutenzione giornaliera elimina definitivamente i messaggi più vecchi di **6 mesi dall’invio** e le notifiche/consegne push associate. Admin può cambiare il periodo da **Manutenzione → Mesi di conservazione messaggi** (1–120 mesi); la soglia attuale è indicata nella casella Messaggi. Un periodo più breve si applica alla prossima esecuzione anche ai messaggi già esistenti. L’eliminazione del profilo può anticipare la cancellazione tramite le FK già configurate. La bozza dei termini 1.0 descrive questa distinzione; durate e rotazione dei backup restano da definire nella bozza.
