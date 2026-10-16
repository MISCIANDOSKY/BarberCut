# Disponibilità database sul piano gratuito

È configurato un controllo esterno GitHub Actions ogni sei ore, alle 01:17, 07:17, 13:17 e 19:17 UTC. Non dipende dal PC del titolare o da un cliente che tenga aperta la PWA.

Il controllo esegue una vera SELECT di sola lettura sul solo campo pubblico app_settings.id. Usa la chiave publishable già presente nel frontend, senza password, service-role o token amministrativi. Non crea clienti, appuntamenti o dati fittizi.

Ogni esecuzione verifica prima il funzionamento dello script con test isolati, quindi contatta il database reale. Errori HTTP, assenza di rete e risposta inattesa fanno fallire il job Database availability. Le notifiche di GitHub dipendono dalle preferenze personali del titolare.

## Limiti da conoscere

Supabase può mettere in pausa progetti Free con attività bassa su un periodo di sette giorni. La documentazione indica che tipicamente alcune richieste utente al database al giorno sono sufficienti, senza garantirlo. Il controllo automatico riduce il rischio, ma non costituisce una garanzia di disponibilità.

GitHub può ritardare i job pianificati; nei repository pubblici li disattiva dopo 60 giorni senza attività del repository. Non vengono creati commit fittizi per aggirare questa regola. Se necessario riattivare il workflow nella sezione Actions.

Se il progetto è già in pausa, questa lettura non lo riattiva: va ripreso dal pannello Supabase. Nessun token amministrativo è stato aggiunto al workflow.

La garanzia di esclusione dalla pausa per inattività richiede un piano Supabase a pagamento. Non è stato cambiato il piano né attivato alcun costo.

Fonti:
- https://supabase.com/docs/guides/platform/free-project-pausing
- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule
