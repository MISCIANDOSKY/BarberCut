import { supabase, result } from "./api";
export type PushSettings = { enabled: boolean; public_key: string | null };
const OWNER = "barberup-push-device-owner";
export function pushCapability() {
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const installed = matchMedia("(display-mode: standalone)").matches || !!(navigator as Navigator & {standalone?: boolean}).standalone;
  return {
    needsHome: ios && !installed,
    supported: window.isSecureContext && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window && (!ios || installed),
    permission: "Notification" in window ? Notification.permission : "default" as NotificationPermission,
  };
}
function storedOwner() { try { return localStorage.getItem(OWNER); } catch { return null; } }
function saveOwner(id: string | null) { try { if (id) localStorage.setItem(OWNER, id); else localStorage.removeItem(OWNER); } catch {} }
export function promptWasSeen(userId: string) { try { return localStorage.getItem("barberup-push-prompt:" + userId) === "seen"; } catch { return false; } }
export function dismissPushPrompt(userId: string) { try { localStorage.setItem("barberup-push-prompt:" + userId, "seen"); } catch {} }
export const readPushSettings = () => result<PushSettings>(supabase.rpc("push_settings"));
async function registration() {
  const scope = new URL(import.meta.env.BASE_URL, location.origin).href;
  return await navigator.serviceWorker.getRegistration(scope) || await navigator.serviceWorker.register(import.meta.env.BASE_URL + "sw.js");
}
function keyBytes(value: string) {
  const raw = atob(value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4));
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}
export async function currentPushSubscription(userId: string) {
  if (!pushCapability().supported) return null;
  const sub = await (await registration()).pushManager.getSubscription();
  if (sub && storedOwner() !== userId) {
    await sub.unsubscribe();
    saveOwner(null);
    return null;
  }
  return sub;
}
export async function syncPush(userId: string, settings: PushSettings) {
  const capability = pushCapability();
  if (!capability.supported || capability.permission !== "granted") return false;
  const sub = await currentPushSubscription(userId);
  if (!settings.enabled || !sub) return false;
  await result(supabase.rpc("register_push_subscription", {p_subscription: sub.toJSON()}));
  return true;
}
export async function enablePush(userId: string, publicKey: string) {
  const capability = pushCapability();
  if (!capability.supported) throw new Error(capability.needsHome ? "Su iPhone aggiungi BarberUp alla schermata Home e aprila dalla sua icona. Serve iOS 16.4 o successivo." : "Questo browser non supporta le notifiche push. Prova una versione aggiornata di Safari, Chrome o Edge.");
  // Called directly by the user's click, before any network request.
  const permission = await Notification.requestPermission();
  if (permission !== "granted") throw new Error("Le notifiche non sono consentite dal dispositivo. Puoi abilitarle nelle impostazioni di BarberUp o del browser.");
  let sub = await currentPushSubscription(userId);
  if (!sub) {
    const worker = await registration();
    await navigator.serviceWorker.ready;
    sub = await worker.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: keyBytes(publicKey)});
  }
  saveOwner(userId);
  try {
    await result(supabase.rpc("register_push_subscription", {p_subscription: sub.toJSON()}));
    await result(supabase.rpc("set_push_enabled", {p_enabled: true}));
  } catch (error) {
    await sub.unsubscribe().catch(() => false);
    saveOwner(null);
    throw error;
  }
  dismissPushPrompt(userId);
  window.dispatchEvent(new Event("barberup:push-changed"));
}
export async function disablePush() {
  await result(supabase.rpc("set_push_enabled", {p_enabled: false}));
  if ("serviceWorker" in navigator) {
    const worker = await navigator.serviceWorker.getRegistration(new URL(import.meta.env.BASE_URL, location.origin).href);
    const sub = await worker?.pushManager?.getSubscription();
    await sub?.unsubscribe();
    const notices = await worker?.getNotifications();
    notices?.forEach((notice) => notice.close());
  }
  saveOwner(null);
  window.dispatchEvent(new Event("barberup:push-changed"));
}
export async function detachPushDevice() {
  if (!("serviceWorker" in navigator)) return;
  try {
    const worker = await navigator.serviceWorker.getRegistration(new URL(import.meta.env.BASE_URL, location.origin).href);
    const sub = await worker?.pushManager?.getSubscription();
    if (sub) {
      await supabase.rpc("unregister_push_subscription", {p_endpoint: sub.endpoint});
      await sub.unsubscribe();
    }
    const notices = await worker?.getNotifications();
    notices?.forEach((notice) => notice.close());
  } catch {
    // Logout remains available offline; an expired subscription is also removed by the sender.
  } finally { saveOwner(null); }
}
