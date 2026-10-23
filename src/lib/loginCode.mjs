export async function sendExistingAccountCode(auth, email, redirectTo) {
  const { error } = await auth.signInWithOtp({
    email: email.trim(),
    options: { shouldCreateUser: false, emailRedirectTo: redirectTo },
  });
  if (error) throw error;
}

export function loginCodeError(error) {
  const code = error?.code;
  const message = error?.message || String(error);
  // Auth also uses otp_disabled when create_user=false cannot find an account.
  // Match that specific response, not every disabled OTP configuration.
  if (
    code === "user_not_found" ||
    /signups not allowed for otp/i.test(message)
  ) {
    return "Per accedere con codice devi avere un account. Controlla l’email inserita oppure registrati.";
  }
  if (code === "user_banned") {
    return "Il tuo account è disattivato. Contatta la barberia per assistenza.";
  }
  if (code === "email_not_confirmed") {
    return "Conferma la tua email per completare la registrazione prima di accedere.";
  }
  if (
    error?.status === 429 ||
    code === "over_email_send_rate_limit" ||
    code === "over_request_rate_limit"
  ) {
    return "Hai richiesto troppi codici. Riprova fra qualche minuto.";
  }
  if (/fetch|network|offline/i.test(message)) {
    return "Connessione assente. Controlla la connessione e riprova.";
  }
  return "Errore nell’invio, riprovare fra qualche minuto.";
}
