import type { SupabaseClient } from "@supabase/supabase-js";
export function sendExistingAccountCode(
  auth: SupabaseClient["auth"],
  email: string,
  redirectTo: string,
): Promise<void>;
export function loginCodeError(error: unknown): string;
