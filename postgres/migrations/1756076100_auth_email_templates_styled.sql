-- styled auth email templates
-- rendered via comms.render_email_template with ${var} substitution

-- ═══════════════════════════════════════════════════════════════════════════
-- magic login link email
-- ═══════════════════════════════════════════════════════════════════════════

insert into comms.email_template (template_key, subject, body, body_params, description)
values (
    'magic_login_link_email',
    'Sign in to Chatterbox',
$$<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="light only" />
  <title>Sign in to Chatterbox</title>
  <style>
    .btn:hover { background-color: #6e9494 !important; }
  </style>
</head>
<body style="margin:0; padding:0; background:#f5f4ee;">

  <!-- preheader (hidden preview text) -->
  <div style="display:none; max-height:0; overflow:hidden; opacity:0; color:transparent;">
    Your sign-in link expires in ${minutes} min.
  </div>

  <!-- outer wrapper -->
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"
         style="background:#f5f4ee; padding:28px 12px;">
    <tr>
      <td align="center">

        <!-- card container -->
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"
               style="max-width:480px;">

          <!-- white card -->
          <tr>
            <td align="center"
                style="
                  background: #ffffff;
                  border-radius: 28px;
                  padding: 26px 22px;
                  box-shadow: 0 10px 30px rgba(0,0,0,0.08);
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                  color: #111827;
                ">

              <!-- logo -->
              <img
                src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
                width="72" height="72" alt="Chatterbox"
                style="display:block; border-radius:18px; margin:0 auto 20px auto;"
              />

              <!-- title -->
              <div style="font-size:20px; font-weight:700; line-height:1.2; margin:0 0 12px 0; text-align:center;">
                Sign in to Chatterbox
              </div>

              <!-- subtitle -->
              <div style="font-size:14px; line-height:1.55; color:#6b7280; margin:0 0 22px 0; text-align:center;">
                Tap the button below to sign in. Expires in <strong>${minutes}</strong> minutes.
              </div>

              <!-- cta button -->
              <table role="presentation" cellspacing="0" cellpadding="0" border="0"
                     style="margin:0 auto 20px auto;">
                <tr>
                  <td bgcolor="#7FA3A3" style="border-radius:16px;">
                    <a href="${url}" class="btn" target="_blank" rel="noopener noreferrer"
                       style="
                         display: inline-block;
                         padding: 14px 22px;
                         font-size: 14px;
                         font-weight: 700;
                         color: #ffffff;
                         text-decoration: none;
                         border-radius: 16px;
                         background: #7FA3A3;
                       ">
                      Open Chatterbox
                    </a>
                  </td>
                </tr>
              </table>

              <!-- fallback link label -->
              <div style="font-size:12px; line-height:1.55; color:#6b7280; margin:0 0 14px 0; text-align:center;">
                If the button doesn't work, use this link:
              </div>

              <!-- fallback link box -->
              <div style="
                background: #f2f2f2;
                border-radius: 6px;
                padding: 12px;
                font-size: 12px;
                line-height: 1.5;
                color: #111827;
                word-break: break-all;
                -webkit-user-select: all;
                user-select: all;
                text-align: left;
                margin: 0 0 16px 0;
              ">
                ${url}
              </div>

              <!-- disclaimer -->
              <div style="font-size:12px; line-height:1.55; color:#6b7280; margin:0; text-align:center;">
                If you didn't request this, you can ignore this email.
              </div>

            </td>
          </tr>

          <!-- footer -->
          <tr>
            <td align="center"
                style="
                  padding: 16px 0 0 0;
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                  color: #9ca3af;
                  font-size: 12px;
                ">
              &copy; Chatterbox
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>

</body>
</html>$$,
    array['url', 'minutes'],
    'Magic login link email template (styled)'
)
on conflict (template_key) do update
set subject     = excluded.subject,
    body         = excluded.body,
    body_params  = excluded.body_params,
    description  = excluded.description;

-- ═══════════════════════════════════════════════════════════════════════════
-- login with code email
-- ═══════════════════════════════════════════════════════════════════════════

insert into comms.email_template (template_key, subject, body, body_params, description)
values (
    'login_with_code',
    'Your Chatterbox sign-in code',
$$<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="light only" />
  <title>Your sign-in code</title>
</head>
<body style="margin:0; padding:0; background:#f5f4ee;">

  <!-- preheader (hidden preview text) -->
  <div style="display:none; max-height:0; overflow:hidden; opacity:0; color:transparent;">
    Your sign-in code is ${code}. Expires in ${minutes} min.
  </div>

  <!-- outer wrapper -->
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"
         style="background:#f5f4ee; padding:28px 12px;">
    <tr>
      <td align="center">

        <!-- card container -->
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"
               style="max-width:480px;">

          <!-- white card -->
          <tr>
            <td align="center"
                style="
                  background: #ffffff;
                  border-radius: 28px;
                  padding: 26px 22px;
                  box-shadow: 0 10px 30px rgba(0,0,0,0.08);
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                  color: #111827;
                ">

              <!-- logo -->
              <img
                src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
                width="72" height="72" alt="Chatterbox"
                style="display:block; border-radius:18px; margin:0 auto 20px auto;"
              />

              <!-- title -->
              <div style="font-size:20px; font-weight:700; line-height:1.2; margin:0 0 12px 0; text-align:center;">
                Your sign-in code
              </div>

              <!-- subtitle -->
              <div style="font-size:14px; line-height:1.55; color:#6b7280; margin:0 0 20px 0; text-align:center;">
                Paste this code into the app. Expires in <strong>${minutes}</strong> minutes.
              </div>

              <!-- code pill -->
              <div style="
                display: inline-block;
                padding: 14px 16px;
                border-radius: 18px;
                background: rgba(179,203,192,0.2);
                border: 1px solid rgba(127,163,163,0.55);
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
                font-size: 28px;
                letter-spacing: 6px;
                font-weight: 700;
                color: #111827;
                -webkit-user-select: all;
                user-select: all;
                margin: 0 0 20px 0;
              ">
                ${code}
              </div>

              <!-- disclaimer -->
              <div style="font-size:12px; line-height:1.55; color:#6b7280; margin:0; text-align:center;">
                If you didn't request this, you can ignore this email.
              </div>

            </td>
          </tr>

          <!-- footer -->
          <tr>
            <td align="center"
                style="
                  padding: 16px 0 0 0;
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                  color: #9ca3af;
                  font-size: 12px;
                ">
              &copy; Chatterbox
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>

</body>
</html>$$,
    array['code', 'minutes'],
    'Login with code email template (styled)'
)
on conflict (template_key) do update
set subject     = excluded.subject,
    body         = excluded.body,
    body_params  = excluded.body_params,
    description  = excluded.description;
