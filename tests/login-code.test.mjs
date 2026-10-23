import test from "node:test";
import assert from "node:assert/strict";
import {
  sendExistingAccountCode,
  loginCodeError,
} from "../src/lib/loginCode.mjs";

test("OTP login preserves structured Auth errors and never creates accounts", async () => {
  const failure = {
    code: "otp_disabled",
    status: 422,
    message: "Signups not allowed for otp",
  };
  let request;
  const auth = {
    async signInWithOtp(value) {
      request = value;
      return { error: failure };
    },
  };
  await assert.rejects(
    sendExistingAccountCode(
      auth,
      " client@example.invalid ",
      "https://example.invalid/",
    ),
    (error) => error === failure,
  );
  assert.deepEqual(request, {
    email: "client@example.invalid",
    options: {
      shouldCreateUser: false,
      emailRedirectTo: "https://example.invalid/",
    },
  });
  assert.match(
    loginCodeError(failure),
    /Controlla l’email inserita oppure registrati/,
  );
  assert.doesNotMatch(loginCodeError(failure), /invio|bloccato/);
});

test("only missing-account responses suggest registration", () => {
  assert.match(loginCodeError({ code: "user_not_found" }), /registrati/);
  assert.match(
    loginCodeError(new Error("Signups not allowed for otp")),
    /registrati/,
  );
  assert.doesNotMatch(
    loginCodeError({ code: "otp_disabled", message: "OTP login disabled" }),
    /registrati/,
  );
  assert.match(
    loginCodeError({ code: "user_banned" }),
    /account è disattivato/,
  );
  assert.match(
    loginCodeError({ code: "email_not_confirmed" }),
    /Conferma la tua email/,
  );
});

test("delivery, throttling and network failures remain distinct", () => {
  for (const failure of [
    { status: 429 },
    { code: "over_email_send_rate_limit" },
    { code: "over_request_rate_limit" },
  ]) {
    assert.match(loginCodeError(failure), /troppi codici/);
  }
  assert.match(loginCodeError(new TypeError("Failed to fetch")), /Connessione/);
  assert.equal(
    loginCodeError({ status: 500, message: "Error sending magic link email" }),
    "Errore nell’invio, riprovare fra qualche minuto.",
  );
});

test("successful delivery uses existing-account OTP options", async () => {
  await sendExistingAccountCode(
    {
      async signInWithOtp(request) {
        assert.equal(request.options.shouldCreateUser, false);
        return { error: null };
      },
    },
    "client@example.invalid",
    "https://example.invalid/",
  );
});
