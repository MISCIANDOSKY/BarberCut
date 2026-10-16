# Accesso con codice email

Dal collegamento “Accedi con codice di verifica” si può richiedere un OTP per un account già esistente. Se l’email è già compilata, il collegamento invia subito il codice. In alternativa si inserisce l’indirizzo nella schermata dedicata. Non viene creato un nuovo account (`shouldCreateUser: false`).

La verifica usa `verifyOtp` con tipo `email`, senza password. Il reinvio richiede 60 secondi. La conferma della registrazione conserva il proprio flusso e il reinvio signup.

Anche admin e barbieri possono accedere tramite codice email. L’Edge Function valida il token con Supabase Auth, controlla un metodo OTP/magiclink degli ultimi 15 minuti e associa l’autorizzazione staff alla sessione attiva tramite `staff_authorize_session`. Nessun ruolo è letto da user_metadata. Il login con password rimane disponibile e per lo staff continua a richiedere la verifica email.

Il modello email Magic link or OTP è configurato in italiano con `{{ .Token }}` e un collegamento alternativo. Nessuna password o chiave SMTP viene salvata nel repository.
