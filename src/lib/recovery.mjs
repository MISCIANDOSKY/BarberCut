export async function sendRecoveryEmail(auth, email, redirectTo) {
  const {error} = await auth.resetPasswordForEmail(email.trim(), {redirectTo});
  if (error) throw error;
}
export async function verifyRecoveryCode(auth, email, token) {
  const {data,error} = await auth.verifyOtp({email:email.trim(),token:token.trim(),type:"recovery"});
  if (error) throw error;
  if (!data?.session) throw new Error("RECOVERY_SESSION_REQUIRED");
  return data.session;
}
