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
    [Alias('Send-SGMessage','Send-SGMail')]
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
        [Alias('Recipient')]
        [MailAddress[]]$CC,

        # An array of recipients who will receive a blind copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 4,
            Mandatory = $true
        )]
        [Alias('Recipient')]
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
            Mandatory = $true
        )]
        [string]$Body
    )
    
    process {
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
                    type  = 'text/plain'
                    value = $Body
                }
            )
        }

        try {
            Invoke-SendGrid -Method 'Post' -Namespace 'mail/send' -ContentBody $ContentBody -ErrorAction Stop
        }
        catch {
            Write-Error ('Failed to send email via SendGrid API. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}
