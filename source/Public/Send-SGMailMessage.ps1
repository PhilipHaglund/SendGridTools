function Send-SGMailMessage {
    <#
    .SYNOPSIS
        Send an email using SendGrid.

    .DESCRIPTION
        Send-SGMailMessage sends an email via the SendGrid API. 

    .PARAMETER From
        Specifies the sender's email address.

    .PARAMETER To
        Specifies the recipient's email address.

    .PARAMETER Subject
        Specifies the email subject.

    .PARAMETER Body
        Specifies the email body.

    .PARAMETER CC
        Specifies the CC email address.

    .PARAMETER BCC
        Specifies the BCC email address.

    .EXAMPLE
        PS C:\> Send-SGMailMessage -From 'sender@example.com' -To 'recipient@example.com' -Subject 'Test Email' -Body 'Hello, this is a test email.'
        
        This command sends an email with the specified parameters via the SendGrid API.
    #>
    [CmdletBinding()]
    [Alias('Send-SGMessage', 'Send-SGMail')]
    param (
        # Specifies the sender's email address.
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [MailAddress]$From,

        # One or an array of recipients who will receive your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 1,
            Mandatory = $true
        )]
        [Alias('Recipient')]
        [MailAddress[]]$To,

        # An array of recipients who will receive a copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 3,
            Mandatory = $true
        )]
        [MailAddress[]]$CC,

        # An array of recipients who will receive a blind copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 4,
            Mandatory = $true
        )]
        [MailAddress[]]$BCC,

        # Specifies the email subject. Limited to 128 chars, because you should write a proper subject... :D
        [Parameter(
            Position = 5,
            Mandatory = $true
        )]
        [ValidateLength(1, 128)]
        [string]$Subject,

        # Specifies the email body.
        [Parameter(
            Mandatory = $true,
            Position = 6
        )]
        [string]$Body,

        # Specifies if the email body is formatted as HTML.
        [Parameter(
            Position = 7
        )]
        [switch]$BodyAsHtml,

        # Specifies the attachment(s) to be included in the email.
        [Parameter()]
        [Alias('Attachments')]
        [System.Net.Mail.Attachment[]]$Attachment,

        # Specifies the email priority. Valid values are 'Low', 'Normal', and 'High'.
        [Parameter()]
        [Alias('Importance')]
        [ValidateSet('Low', 'Normal', 'High')]
        [string]$Priority,

        # Specifies if Separate To should be used.
        [Parameter()]
        [switch]$SeperateTo,

        # Specifies if a separate ReplyTo address should be used.
        [Parameter()]
        [MailAddress]$ReplyTo,

        # Specifies the date and time to send the email. If not specified, the email will be sent immediately.
        [Parameter()]
        [UnixTime]$SendAt

    )
    
    process {
        # Convert the MailAddress objects to SendGrid API compatible objects.
        $FromList = ConvertTo-SendGridAddress -Address $From
        $ToList   = ConvertTo-SendGridAddress -Address $To
        $CCList   = ConvertTo-SendGridAddress -Address $CC
        $BCCList  = ConvertTo-SendGridAddress -Address $BCC

        if ($PSBoundParameters.ContainsKey('ReplyTo')) {
            $ReplyToList = ConvertTo-SendGridAddress -Address $ReplyTo
        }

        [hashtable]$ContentBody = @{
            personalizations = @(
                @{
                    to      = @(@{ email = $To })
                    cc      = @(@{ email = $CC })   # Please note that this will need additional processing if multiple CC addresses are provided
                    bcc     = @(@{ email = $BCC })  # Please note that this will need additional processing if multiple BCC addresses are provided
                    subject = $Subject
                }
            )
            from             = @{
                email = $From
            }
            content          = @(
                @{
                    type  =  if ($BodyAsHtml) { 'text/html' } else { 'text/plain' }
                    value = $Body
                }
            )
            attachments      = @(
                foreach ($A in $Attachment) {
                    @{
                        content     = [Convert]::ToBase64String([IO.File]::ReadAllBytes($A.ContentStream.Name))
                        filename    = $A.Name
                        type        = $A.ContentType
                        disposition = 'attachment'
                    }
                }
            )
            send_at          = $SendAt
        }

        try {
            Invoke-SendGrid -Method 'Post' -Namespace 'mail/send' -ContentBody $ContentBody -ErrorAction Stop
        }
        catch {
            Write-Error ('Failed to send email via SendGrid API. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}
