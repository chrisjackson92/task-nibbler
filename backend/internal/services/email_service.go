package services

import (
	"context"
	"fmt"

	resend "github.com/resend/resend-go/v2"
)

// EmailService wraps the Resend SDK for sending transactional emails.
// The raw reset token is passed through but NEVER logged (GOV-006 compliance).
type EmailService struct {
	client    *resend.Client
	fromEmail string
	baseURL   string
}

// NewEmailService creates a new EmailService.
func NewEmailService(apiKey, fromEmail, baseURL string) *EmailService {
	return &EmailService{
		client:    resend.NewClient(apiKey),
		fromEmail: fromEmail,
		baseURL:   baseURL,
	}
}

// SendPasswordReset sends a branded password reset email via Resend.
// The rawToken is included in the link URL — it is NEVER logged.
func (s *EmailService) SendPasswordReset(ctx context.Context, toEmail, rawToken string) error {
	resetURL := fmt.Sprintf("%s/reset-password?token=%s", s.baseURL, rawToken)

	params := &resend.SendEmailRequest{
		From:    s.fromEmail,
		To:      []string{toEmail},
		Subject: "Reset your Task Nibbles password",
		Html:    buildPasswordResetHTML(resetURL),
	}

	_, err := s.client.Emails.Send(params)
	if err != nil {
		return fmt.Errorf("resend: send email: %w", err)
	}

	return nil
}

// buildPasswordResetHTML returns a simple branded HTML email body.
// The resetURL is embedded once in the CTA button href.
func buildPasswordResetHTML(resetURL string) string {
	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Reset your Task Nibbles password</title>
</head>
<body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">
  <table width="100%%" cellpadding="0" cellspacing="0">
    <tr>
      <td align="center" style="padding:40px 0;">
        <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;">
          <tr>
            <td style="background:#1a1a2e;padding:32px;text-align:center;">
              <h1 style="color:#ffffff;margin:0;font-size:24px;">🌱 Task Nibbles</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:40px 48px;">
              <h2 style="color:#1a1a2e;font-size:20px;margin:0 0 16px;">Reset your password</h2>
              <p style="color:#555;font-size:16px;line-height:1.6;margin:0 0 24px;">
                We received a request to reset your Task Nibbles password.
                Click the button below to set a new password. This link expires in <strong>1 hour</strong>.
              </p>
              <div style="text-align:center;margin:32px 0;">
                <a href="%s"
                   style="background:#6c63ff;color:#ffffff;text-decoration:none;
                          padding:14px 32px;border-radius:6px;font-size:16px;font-weight:bold;
                          display:inline-block;">
                  Reset Password
                </a>
              </div>
              <p style="color:#888;font-size:14px;line-height:1.6;margin:24px 0 0;">
                If you did not request a password reset, you can safely ignore this email.
                Your password will not change.
              </p>
            </td>
          </tr>
          <tr>
            <td style="background:#f9f9f9;padding:24px 48px;text-align:center;">
              <p style="color:#aaa;font-size:12px;margin:0;">
                Task Nibbles · noreply@tasknibbles.com
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`, resetURL)
}
