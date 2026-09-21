const nodemailer = require('nodemailer');
require('dotenv').config();

async function testSmtp() {
  console.log('--- TESTING SMTP DELIVERY ---');
  console.log('Host:', process.env.SMTP_HOST);
  console.log('Port:', process.env.SMTP_PORT);
  console.log('User:', process.env.SMTP_USER);

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT || '587'),
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS
    },
    tls: {
      rejectUnauthorized: false
    }
  });

  const startTime = Date.now();
  try {
    const info = await transporter.sendMail({
      from: `"RO Wholesale Security" <${process.env.SMTP_USER}>`,
      to: 'priyaangel61003@gmail.com',
      subject: '🔐 Immediate Security OTP Code: 884920',
      text: 'Your RO Wholesale Security Code is: 884920. This code is valid for 5 minutes.',
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; background: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px;">
          <h2 style="color: #0f62fe; margin: 0 0 12px 0;">RO Wholesale Security</h2>
          <p style="font-size: 14px; color: #334155;">Your verification code for <strong>priyaangel61003@gmail.com</strong> is:</p>
          <div style="background: #0f62fe; color: #ffffff; font-size: 36px; font-weight: bold; letter-spacing: 10px; padding: 14px 20px; border-radius: 8px; text-align: center; margin: 16px 0;">
            884920
          </div>
          <p style="font-size: 12px; color: #64748b;">This code will expire in 5 minutes.</p>
        </div>
      `
    });
    const elapsed = Date.now() - startTime;
    console.log(`✅ SUCCESS in ${elapsed}ms!`);
    console.log('Message ID:', info.messageId);
    console.log('Accepted:', info.accepted);
    console.log('Rejected:', info.rejected);
    console.log('Response:', info.response);
  } catch (err) {
    console.error('❌ FAILED:', err);
  }
}

testSmtp();
