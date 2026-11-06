'use strict';

// Safe by default: checks configuration without sending mail or opening SMTP.
// In Render Shell: node test_smtp.js
// Explicit delivery smoke test: node test_smtp.js --send-to <test-recipient>
const { createEmailSender, getEmailConfiguration } = require('./email_provider');

async function main(args = process.argv.slice(2)) {
  require('dotenv').config({ quiet: true });
  const configuration = getEmailConfiguration();
  console.log('[EMAIL configuration]', JSON.stringify(configuration));
  if (!configuration.configured) { process.exitCode = 1; return; }
  if (!args.length) return;
  if (args.length !== 2 || args[0] !== '--send-to' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(args[1])) {
    console.error('Usage: node test_smtp.js [--send-to <test-recipient>]');
    process.exitCode = 1;
    return;
  }
  const send = createEmailSender({ smtpTransportFactory: options => require('nodemailer').createTransport(options) });
  try {
    const result = await send({ to: args[1], subject: 'RO Wholesale email delivery test',
      text: 'This is an email delivery test. No login code or session is created.',
      html: '<p>This is an email delivery test. No login code or session is created.</p>' });
    console.log('[EMAIL provider accepted]', JSON.stringify({ provider: result.provider, accepted: result.accepted.length > 0 }));
  } catch (error) {
    console.error('[EMAIL delivery failed]', JSON.stringify({ provider: error.provider, code: error.code, status: error.status || null }));
    process.exitCode = 1;
  }
}

if (require.main === module) main().catch(() => { console.error('Email diagnostic failed.'); process.exitCode = 1; });
module.exports = { main };
