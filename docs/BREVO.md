# Email di registrazione BarberCut

Mittente richiesto: BarberCut <ciaosirimborsa@gmail.com>, già verificato nell'account Brevo del titolare.

Configurazione prevista in Supabase BarberCut > Authentication > Emails > SMTP Settings:
- Host: smtp-relay.brevo.com
- Porta: 587 (STARTTLS)
- Nome mittente: BarberCut
- Email mittente: ciaosirimborsa@gmail.com
- Login SMTP e chiave SMTP: solo nel pannello Supabase, mai nel repository.

La chiave SMTP va recuperata dal titolare o generata da lui in Brevo; non ruotare le chiavi utilizzate da altri progetti.

Dopo l'attivazione SMTP, in Confirm sign up impostare l'oggetto «Il tuo codice per completare la registrazione a BarberCut» e copiare il contenuto di supabase/templates/confirmation.html. Il codice reale è generato da Supabase tramite {{ .Token }}; il link alternativo usa {{ .ConfirmationURL }}. L'app dispone della schermata di verifica codice e reinvio della conferma con attesa di 60 secondi.

Stato: modello e flusso app pronti. Attivazione del mittente Brevo e modello email da verificare dopo l'inserimento delle credenziali SMTP. Nessuna email di prova inviata.
