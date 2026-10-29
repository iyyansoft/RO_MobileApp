'use strict';

const BREVO_TRANSACTIONAL_EMAIL_URL = 'https://api.brevo.com/v3/smtp/email';

function sanitizedEmailError(provider, code, status) {
  const error = new Error(`${provider} email delivery failed`);
  error.code = code || 'EMAIL_DELIVERY_FAILED';
  if (Number.isInteger(status)) error.status = status;
  error.provider = provider;
  return error;
}

function parseSender(value, configuredName) {
  value = String(value || '').trim();
  const match = value.match(/^(.*?)\s*<([^<>]+)>$/);
  const email = (match ? match[2] : value).trim();
  if (!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(email)) return null;
  const name = String(configuredName || match?.[1] || '').replace(/^"|"$/g, '').trim();
  return { email, ...(name ? { name } : {}) };
}

function brevoSenderFromEnvironment(env) {
  return parseSender(env.BREVO_SENDER_EMAIL, env.BREVO_SENDER_NAME);
}

function smtpSenderFromEnvironment(env) {
  return parseSender(env.SMTP_FROM);
}

function createEmailSender({ env = process.env, fetchImpl = globalThis.fetch, smtpTransportFactory } = {}) {
  let smtpTransport;

  function smtpOptions() {
    const host = String(env.SMTP_HOST || '').trim();
    const port = Number(env.SMTP_PORT);
    const user = String(env.SMTP_USER || '').trim();
    const pass = String(env.SMTP_PASS || '');
    const secureValue = String(env.SMTP_SECURE || '').trim().toLowerCase();
    const validPortMode = (port === 465 && secureValue === 'true') || (port === 587 && secureValue === 'false');
    if (!host || !user || !pass || !validPortMode || !smtpSenderFromEnvironment(env)) return null;
    return {
      host,
      port,
      secure: port === 465,
      auth: { user, pass },
      tls: { rejectUnauthorized: true },
      ...(port === 587 ? { requireTLS: true } : {}),
      connectionTimeout: Number(env.SMTP_CONNECTION_TIMEOUT_MS) || 6000,
      greetingTimeout: Number(env.SMTP_GREETING_TIMEOUT_MS) || 6000,
      socketTimeout: Number(env.SMTP_SOCKET_TIMEOUT_MS) || 8000
    };
  }

  async function sendWithBrevo(message, apiKey, sender) {
    if (typeof fetchImpl !== 'function') throw sanitizedEmailError('brevo', 'FETCH_UNAVAILABLE');
    let response;
    try {
      response = await fetchImpl(BREVO_TRANSACTIONAL_EMAIL_URL, {
        method: 'POST',
        headers: { accept: 'application/json', 'content-type': 'application/json', 'api-key': apiKey },
        body: JSON.stringify({
          sender,
          to: [{ email: message.to }],
          subject: message.subject,
          textContent: message.text,
          htmlContent: message.html
        }),
        redirect: 'error',
        signal: AbortSignal.timeout(Number(env.EMAIL_REQUEST_TIMEOUT_MS) || 10000)
      });
    } catch (cause) {
      throw sanitizedEmailError('brevo', cause?.name === 'TimeoutError' || cause?.name === 'AbortError' ? 'EMAIL_PROVIDER_TIMEOUT' : 'EMAIL_PROVIDER_NETWORK_ERROR');
    }
    if (!response?.ok) throw sanitizedEmailError('brevo', 'EMAIL_PROVIDER_REJECTED', response?.status);
    return { accepted: [message.to], provider: 'brevo' };
  }

  async function sendWithSmtp(message, sender, options) {
    if (typeof smtpTransportFactory !== 'function') throw sanitizedEmailError('smtp', 'SMTP_TRANSPORT_UNAVAILABLE');
    try {
      smtpTransport ||= smtpTransportFactory(options);
      const result = await smtpTransport.sendMail({
        from: String(env.SMTP_FROM).trim(), to: message.to,
        subject: message.subject, text: message.text, html: message.html
      });
      const accepted = Array.isArray(result?.accepted) ? result.accepted : [];
      if (!accepted.some(recipient => String(recipient).toLowerCase() === String(message.to).toLowerCase())) {
        throw sanitizedEmailError('smtp', 'EMAIL_PROVIDER_REJECTED', result?.responseCode);
      }
      return { accepted: [message.to], provider: 'smtp' };
    } catch (cause) {
      if (cause?.provider === 'smtp') throw cause;
      throw sanitizedEmailError('smtp', cause?.code || 'EMAIL_PROVIDER_ERROR', cause?.responseCode);
    }
  }

  return async function sendTransactionalEmail(message) {
    const apiKey = String(env.BREVO_API_KEY || '').trim();
    if (apiKey) {
      const sender = brevoSenderFromEnvironment(env);
      if (!sender) throw sanitizedEmailError('configuration', 'EMAIL_SENDER_NOT_CONFIGURED');
      return sendWithBrevo(message, apiKey, sender);
    }

    const options = smtpOptions();
    if (!options) throw sanitizedEmailError('configuration', 'EMAIL_PROVIDER_NOT_CONFIGURED');
    return sendWithSmtp(message, smtpSenderFromEnvironment(env), options);
  };
}

module.exports = { BREVO_TRANSACTIONAL_EMAIL_URL, createEmailSender };
