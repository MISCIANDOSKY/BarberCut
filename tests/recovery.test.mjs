import test from "node:test";
import assert from "node:assert/strict";
import { sendRecoveryEmail, verifyRecoveryCode } from "../src/lib/recovery.mjs";
test("Invio recupero: email ripulita e redirect della PWA", async () => {
  const calls = [];
  const auth = {
    resetPasswordForEmail: async (...args) => {
      calls.push(args);
      return { error: null };
    },
  };
  await sendRecoveryEmail(
    auth,
    " cliente@example.invalid ",
    "https://example.invalid/app/",
  );
  assert.deepEqual(calls, [
    ["cliente@example.invalid", { redirectTo: "https://example.invalid/app/" }],
  ]);
});
test("OTP usa esclusivamente recovery e richiede una sessione", async () => {
  const calls = [];
  const session = { access_token: "test-only" };
  const auth = {
    verifyOtp: async (args) => {
      calls.push(args);
      return { data: { session }, error: null };
    },
  };
  assert.equal(
    await verifyRecoveryCode(auth, " cliente@example.invalid ", " 123456 "),
    session,
  );
  assert.deepEqual(calls, [
    { email: "cliente@example.invalid", token: "123456", type: "recovery" },
  ]);
  await assert.rejects(
    () =>
      verifyRecoveryCode(
        { verifyOtp: async () => ({ data: { session: null }, error: null }) },
        "a",
        "1",
      ),
    /RECOVERY_SESSION_REQUIRED/,
  );
});
test("Errori invio e OTP propagati senza continuare il cambio password", async () => {
  const error = new Error("expired");
  await assert.rejects(
    () =>
      sendRecoveryEmail(
        { resetPasswordForEmail: async () => ({ error }) },
        "a",
        "b",
      ),
    error,
  );
  await assert.rejects(
    () =>
      verifyRecoveryCode(
        { verifyOtp: async () => ({ error, data: null }) },
        "a",
        "1",
      ),
    error,
  );
});
