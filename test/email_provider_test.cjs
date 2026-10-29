const { test } = require('node:test');
const assert = require('node:assert/strict');
const { BREVO_TRANSACTIONAL_EMAIL_URL, createEmailSender } = require('../email_provider');

const email = {
  to: 'recipient@example.test',
  subject: 'Verification code',
  text: 'Your code is 123456.',
  html: '<p>Your code is <strong>123456</strong>.</p>'
};

test('Brevo sends a transactional message over HTTPS and reports provider acceptance only', async () => {
  let request;
  const send = createEmailSender({
    env: { BREVO_API_KEY: 'test-only-api-key', BREVO_SENDER_EMAIL: 'verified@example.test', BREVO_SENDER_NAME: 'RO Test' },
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 201, json: async () => ({ messageId: 'provider-test-id' }) };
    }
  });

  const result = await send(email);
  assert.equal(request.url, BREVO_TRANSACTIONAL_EMAIL_URL);
  assert.equal(request.options.method, 'POST');
  assert.equal(request.options.redirect, 'error');
  assert.equal(request.options.headers['api-key'], 'test-only-api-key');
  assert.equal(request.options.headers['content-type'], 'application/json');
  assert.deepEqual(JSON.parse(request.options.body), {
    sender: { email: 'verified@example.test', name: 'RO Test' },
    to: [{ email: email.to }], subject: email.subject, textContent: email.text, htmlContent: email.html
  });
  assert.deepEqual(result, { accepted: [email.to], provider: 'brevo' });
});

test('Brevo rejection is sanitized and never falls back to SMTP', async () => {
  let smtpCreated = false;
  const send = createEmailSender({
    env: { BREVO_API_KEY: 'test-only-api-key', BREVO_SENDER_EMAIL: 'verified@example.test', SMTP_HOST: 'smtp.example.test', SMTP_PORT: '465', SMTP_SECURE: 'true', SMTP_USER: 'u', SMTP_PASS: 'p', SMTP_FROM: 'verified@example.test' },
    fetchImpl: async () => ({ ok: false, status: 401, text: async () => 'sensitive provider response body' }),
    smtpTransportFactory: () => { smtpCreated = true; throw new Error('must not fall back'); }
  });

  await assert.rejects(send(email), error => {
    assert.equal(error.code, 'EMAIL_PROVIDER_REJECTED');
    assert.equal(error.status, 401);
    assert.equal(error.provider, 'brevo');
    assert.doesNotMatch(error.message, /test-only-api-key|sensitive provider response body/);
    return true;
  });
  assert.equal(smtpCreated, false);
});

test('network errors are sanitized and no API secret or provider body is surfaced', async () => {
  const send = createEmailSender({
    env: { BREVO_API_KEY: 'test-only-api-key', BREVO_SENDER_EMAIL: 'verified@example.test' },
    fetchImpl: async () => { throw new Error('failed with test-only-api-key and private response'); }
  });
  await assert.rejects(send(email), error => {
    assert.equal(error.code, 'EMAIL_PROVIDER_NETWORK_ERROR');
    assert.doesNotMatch(error.message, /test-only-api-key|private response/);
    return true;
  });
});

test('SMTP fallback requires explicit secure TLS settings and verifies certificates', async () => {
  let transportOptions;
  const send = createEmailSender({
    env: { SMTP_HOST: 'smtp.example.test', SMTP_PORT: '587', SMTP_SECURE: 'false', SMTP_USER: 'user', SMTP_PASS: 'password', SMTP_FROM: 'verified@example.test' },
    fetchImpl: async () => { throw new Error('HTTPS Brevo must not be attempted without a key'); },
    smtpTransportFactory: options => {
      transportOptions = options;
      return { sendMail: async message => ({ accepted: [message.to] }) };
    }
  });
  assert.deepEqual(await send(email), { accepted: [email.to], provider: 'smtp' });
  assert.equal(transportOptions.requireTLS, true);
  assert.equal(transportOptions.secure, false);
  assert.equal(transportOptions.tls.rejectUnauthorized, true);
});

test('SMTP fallback is not used with missing TLS or sender configuration', async () => {
  let smtpCreated = false;
  const send = createEmailSender({
    env: { SMTP_HOST: 'smtp.example.test', SMTP_PORT: '587', SMTP_USER: 'user', SMTP_PASS: 'password' },
    smtpTransportFactory: () => { smtpCreated = true; }
  });
  await assert.rejects(send(email), error => error.code === 'EMAIL_PROVIDER_NOT_CONFIGURED');
  assert.equal(smtpCreated, false);
});
