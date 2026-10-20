# Email di registrazione BarberUp

SMTP Brevo è attivo nel progetto Supabase (nome interno BarberCut).

- Mittente configurato: BarberUp <ciaosirimborsa@gmail.com>
- Host: smtp-relay.brevo.com
- Porta: 587 (STARTTLS)
- Chiave dedicata (nome interno invariato): BarberCut Supabase SMTP, creata il 16 ottobre 2026 con scadenza 16 ottobre 2027. Brevo prevede anche scadenza dopo 90 giorni di inattività.
- Login e chiave SMTP conservati esclusivamente nella configurazione protetta Supabase; nessuna credenziale nel repository.
- Le chiavi e le impostazioni SMTP degli altri progetti sono rimaste intatte.

## Conferma registrazione

In Supabase > Authentication > Emails > Confirm sign up è applicato il modello italiano di supabase/templates/confirmation.html.

Oggetto: Il tuo codice per completare la registrazione a BarberUp

Il corpo include il codice reale generato da Supabase tramite {{ .Token }} e il link alternativo {{ .ConfirmationURL }}. La PWA permette di inserire il codice, completare la registrazione e richiedere una nuova conferma con attesa di 60 secondi.

## Verifica

Configurazione SMTP salvata; editor email sbloccato dopo l'attivazione. Modello italiano salvato e verificato nell'anteprima. La ricezione effettiva nella casella del destinatario resta da controllare alla prossima registrazione: non sono state create nuove utenze né inviate email di prova durante questa configurazione.
