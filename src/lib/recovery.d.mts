import type { SupabaseClient, Session } from "@supabase/supabase-js";
export function sendRecoveryEmail(auth: SupabaseClient["auth"], email: string, redirectTo: string): Promise<void>;
export function verifyRecoveryCode(auth: SupabaseClient["auth"], email: string, token: string): Promise<Session>;
