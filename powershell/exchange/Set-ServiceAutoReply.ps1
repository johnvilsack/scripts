$ExternalMessage = @"
Thank you for contacting SSI Service. We have received your request and one of our team members will get back to you within 24–48 hours during our business hours (Mon–Fri, 8 AM–5 PM CT).

For urgent issues, please call us at 952-848-7448.

We appreciate your patience and look forward to assisting you.

Best regards,
SSI Service Team
"@

Set-MailboxAutoReplyConfiguration -Identity "servicefax@shippers-supply.com" -AutoReplyState Enabled -ExternalMessage $ExternalMessage -InternalMessage " " -ExternalAudience All