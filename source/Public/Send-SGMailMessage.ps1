function Send-SGMailMessage {
    <#
    .SYNOPSIS
        Sends an email via the SendGrid API.

    .DESCRIPTION
        The Send-SGMailMessage function sends an email using the SendGrid API. It allows you to specify the sender, recipient, subject, and body of the email, as well as any attachments.

    .PARAMETER From
        Specifies the sender's email address.

    .PARAMETER To
        One or an array of recipients who will receive your email.
        Each object in this array must contain the recipient's email address.
        Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        'Name name@example.com'
        'Firstname Lastname firstname.lastname@example.com'
        'Firstname Lastname <firstname.lastname@example.com>'
        'Firstname.Lastname firstname.lastname@example.com'
        '"Firstname Lastname" firstname.lastname@example.com'
        '"Firstname Lastname" <firstname.lastname@example.com>'

    .PARAMETER Subject
        Specifies the email subject.

    .PARAMETER Body
        Specifies the email body.

    .PARAMETER CC
        Specifies the CC email address. CC addresses are not visible to the recipients of the email.
        One or an array of CC who will receive your email.
        Each object in this array must contain the recipient's email address.
        Each object in the array may optionally contain the recipient's name.
        'Name<Name@example.com>'
        'Name name@example.com'
        'Firstname Lastname firstname.lastname@example.com'
        'Firstname Lastname <firstname.lastname@example.com>'
        'Firstname.Lastname firstname.lastname@example.com'
        '"Firstname Lastname" firstname.lastname@example.com'
        '"Firstname Lastname" <firstname.lastname@example.com>'

    .PARAMETER BCC
        Specifies the BCC email address. BCC addresses are not visible to the recipients of the email.
        One or an array of BCC who will receive your email.
        Each object in this array must contain the recipient's email address.
        Each object in the array may optionally contain the recipient's name.
        'Name<Name@example.com>'
        'Name name@example.com'
        'Firstname Lastname firstname.lastname@example.com'
        'Firstname Lastname <firstname.lastname@example.com>'
        'Firstname.Lastname firstname.lastname@example.com'
        '"Firstname Lastname" firstname.lastname@example.com'
        '"Firstname Lastname" <firstname.lastname@example.com>'

    .PARAMETER BodyAsHtml
        Specifies if the email body is formatted as HTML. Default is False, i.e. plain text.

    .PARAMETER Attachment
        Specifies the attachment(s) to be included in the email.

    .PARAMETER Priority
        Specifies the email priority. Valid values are 'Low', 'Normal', and 'High'.

    .PARAMETER SeparateTo
        Specifies if Separate To should be used. 

    .PARAMETER ReplyTo
        Specifies if a separate ReplyTo address should be used. If not specified, the sender's email address (From) will be used.
    
    .PARAMETER SendAt
        Specifies the date and time to send the email. If not specified, the email will be sent immediately. Both datetime and unix timestamp formats are accepted.
        A unix timestamp allowing you to specify when your email should be delivered. Scheduling delivery more than 72 hours in advance is forbidden.

    .PARAMETER TemplateId
        Specifies the template ID to use. An email template ID. A template that contains a subject and content — either text or html — will override any subject and content values specified at the personalizations or message level.

    .PARAMETER Categories
        Specifies an array of category names for this message. Each category name may not exceed 255 characters.
    
    .PARAMETER BatchId
        Specifies an ID representing a batch of emails to be sent at the same time. Including a batch_id in your request allows you include this email in that batch. It also enables you to cancel or pause the delivery of that batch. For more information, see the Cancel Scheduled Sends API.

    .EXAMPLE
        PS C:\> Send-SGMailMessage -From 'sender@example.com' -To 'recipient@example.com' -Subject 'Test Email' -Body 'Hello, this is a test email.'
        
        This command sends an email with the specified parameters via the SendGrid API.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        DefaultParameterSetName = 'Default'
    )]
    [Alias('Send-SGMessage', 'Send-SGMail')]
    param (
        # Specifies the sender's email address.
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ParameterSetName = 'Default'
        )]
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ParameterSetName = 'SeparateTo'
        )]
        [MailAddress]$From,

        # One or an array of recipients who will receive your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 1,
            Mandatory = $true,
            ParameterSetName = 'Default'
        )]
        [Parameter(
            Position = 1,
            Mandatory = $true,
            ParameterSetName = 'SeparateTo'
        )]
        [Alias('Recipient')]
        [MailAddress[]]$To,

        # An array of recipients who will receive a copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 2,
            ParameterSetName = 'Default'
        )]
        [MailAddress[]]$CC,

        # An array of recipients who will receive a blind copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name. 'Name<Name@example.com>'
        [Parameter(
            Position = 3,
            ParameterSetName = 'Default'
        )]
        [MailAddress[]]$BCC,

        # Specifies the email subject.
        [Parameter(
            Position = 4,
            Mandatory = $true,
            ParameterSetName = 'Default'
        )]
        [Parameter(
            Position = 4,
            Mandatory = $true,
            ParameterSetName = 'SeparateTo'
        )]
        [ValidateLength(1, 998)]
        [string]$Subject,

        # Specifies the email body. 
        [Parameter(
            Position = 5,
            Mandatory = $true,
            ParameterSetName = 'Default'
        )]
        [Parameter(
            Position = 5,
            Mandatory = $true,
            ParameterSetName = 'SeparateTo'
        )]
        [string]$Body,

        # Specifies if the email body is formatted as HTML.
        [Parameter(
            Position = 6,
            ParameterSetName = 'Default'
        )]
        [Parameter(
            Position = 6,
            ParameterSetName = 'SeparateTo'
        )]
        [switch]$BodyAsHtml,

        # Specifies the attachment(s) to be included in the email.
        [Parameter(
            Position = 7,
            ParameterSetName = 'Default'
        )]
        [Parameter(
            Position = 7, 
            ParameterSetName = 'SeparateTo'
        )]
        [Alias('Attachments')]
        [System.Net.Mail.Attachment[]]$Attachment,

        # Specifies the email priority. Valid values are 'Low', 'Normal', and 'High'.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [Alias('Importance')]
        [ValidateSet('Low', 'Normal', 'High')]
        [string]$Priority,

        # Specifies if Separate To should be used.
        [Parameter(ParameterSetName = 'SeparateTo')]
        [switch]$SeparateTo,

        # Specifies if a separate ReplyTo address should be used.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [MailAddress]$ReplyTo,

        # Specifies the date and time to send the email. If not specified, the email will be sent immediately. Both datetime and unix timestamp formats are accepted.
        # Scheduling delivery more than 72 hours in advance is forbidden.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [UnixTime]$SendAt,

        # Specifies the template ID to use. An email template ID. A template that contains a subject and content — either text or html — will override any subject and content values specified at the personalizations or message level.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [string]$TemplateId,

        # Specifies an array of category names for this message. Each category name may not exceed 255 characters.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [ValidateLength(1, 10)]
        [string[]]$Categories,

        # Specifies an ID representing a batch of emails to be sent at the same time. Including a batch_id in your request allows you include this email in that batch. It also enables you to cancel or pause the delivery of that batch. For more information, see the Cancel Scheduled Sends API.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [string]$BatchId,

        <#
            Specifies an object of type [SGASM] that allows you to specify how to handle unsubscribes.

            The [SGASM] class represents a set of options for handling unsubscribes. It has the following properties:

            - GroupId: An integer that represents the group ID for unsubscribes. Default value is 0.
            - GroupsToDisplay: An array of integers that represents the groups to display for unsubscribes. Default value is an empty array.

            You can create an instance of [SGASM] using the following constructors:
            - SGASM(): Creates an instance with default values for GroupId and GroupsToDisplay.
            - SGASM([int]$GroupId): Creates an instance with the specified GroupId and default value for GroupsToDisplay.
            - SGASM([int]$GroupId, [int[]]$GroupsToDisplay): Creates an instance with the specified GroupId and GroupsToDisplay.

            The ToString() method returns a string representation of the GroupId.

            Example usage:
            $unsubscribe = [SGASM]::new(123, @(1, 2, 3))
            Send-SGMailMessage -Unsubscribe $unsubscribe
        #>
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'SeparateTo')]
        [ValidateNotNullOrEmpty()]
        [SGASM]$Unsubscribe


    )
    begin {
        $InvokeSplat = @{
                Method      = 'Post'
                Namespace   = 'mail/send'
                ErrorAction = 'Stop'
            }
        [hashtable]$ContentBody = @{
            personalizations = [System.Collections.Generic.List[hashtable]]::new()
        }
        $RecipientCount = $To.Count + $CC.Count + $BCC.Count
    }
    process {
        if ($PSCmdlet.ShouldProcess(('{0} to "{1}" recipients with subject: "{2}"' -f $From.Address, $RecipientCount, $Subject))) {
        
            # Convert the MailAddress objects to SendGrid API compatible objects.
            $FromList = ConvertTo-SendGridAddress -Address $From
            $ToList = ConvertTo-SendGridAddress -Address $To
            $CCList = ConvertTo-SendGridAddress -Address $CC
            $BCCList = ConvertTo-SendGridAddress -Address $BCC
            $ReplyToList = ConvertTo-SendGridAddress -Address $ReplyTo
            <#
            Personalizations
            An array of messages and their metadata. Each object within personalizations can be thought of as an envelope - it defines who should receive an individual message and how that message should be handled. See our Personalizations documentation for examples.
            maxItems: 1000
            Personalizations can contain the following fields:
                from
                to
                cc = An array of recipients who will receive a copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name.
                bcc = An array of recipients who will receive a blind carbon copy of your email. Each object in this array must contain the recipient's email address. Each object in the array may optionally contain the recipient's name.
                subject = The subject of your email. See character length requirements according to RFC 2822.
                headers = A collection of JSON key/value pairs allowing you to specify handling instructions for your email. You may not overwrite the following headers: x-sg-id, x-sg-eid, received, dkim-signature, Content-Type, Content-Transfer-Encoding, To, From, Subject, Reply-To, CC, BCC
                substitutions = Substitutions allow you to insert data without using Dynamic Transactional Templates. This field should not be used in combination with a Dynamic Transactional Template, which can be identified by a template_id starting with d-. This field is a collection of key/value pairs following the pattern "substitution_tag":"value to substitute". The key/value pairs must be strings. These substitutions will apply to the text and html content of the body of your email, in addition to the subject and reply-to parameters. The total collective size of your substitutions may not exceed 10,000 bytes per personalization object.
                dynamic_template_data = Dynamic template data is available using Handlebars syntax in Dynamic Transactional Templates. This field should be used in combination with a Dynamic Transactional Template, which can be identified by a template_id starting with d-. This field is a collection of key/value pairs following the pattern "variable_name":"value to insert".
                custom_args = Values that are specific to this personalization that will be carried along with the email and its activity data. Substitutions will not be made on custom arguments, so any string that is entered into this parameter will be assumed to be the custom argument that you would like to be used. This field may not exceed 10,000 bytes.
                send_at = A unix timestamp allowing you to specify when your email should be delivered. Scheduling delivery more than 72 hours in advance is forbidden.
            #>
            if ($SeparateTo) {
                foreach ($T in $To) {
                    $Personalizations = @{
                        subject = $Subject
                        to      = @(
                            ConvertTo-SendGridAddress -Address $T
                        )
                    }
                    $ContentBody.personalizations.Add($Personalizations)
                }
            }
            else {
                $ContentBody.personalizations.Add(@{
                        subject = $Subject
                        to      = @($ToList)
                        cc      = @($CCList)
                        bcc     = @($BCCList)
                    })
            }
            $ContentBody.personalizations | Remove-EmptyHashtable -Recursive
            $ContentBody.Add('from', $FromList)
            if ($PSBoundParameters.ContainsKey('ReplyTo')) {
                $ContentBody.Add('reply_to', $ReplyToList)
            }
            $ContentBody.Add('content', @(
                    @{
                        type  = if ($BodyAsHtml) { 'text/html' } else { 'text/plain' }
                        value = $Body
                    }
                ))
            if ($PSBoundParameters.ContainsKey('Attachment')) {
                $ContentBody.Add('attachments', @(
                        foreach ($A in $Attachment) {
                            @{
                                content     = [Convert]::ToBase64String([IO.File]::ReadAllBytes($A.ContentStream.Name))
                                filename    = $A.Name
                                type        = $A.ContentType.MediaType
                                disposition = 'attachment'
                            }
                        }
                    ))
            }
            if ($PSBoundParameters.ContainsKey('Priority')) {
                $ContentBody.Add('priority', $Priority)
            }
            if ($PSBoundParameters.ContainsKey('SendAt')) {
                $ContentBody.Add('send_at', $SendAt.ToUnixTime())
            }
            if ($PSBoundParameters.ContainsKey('TemplateId')) {
                $ContentBody.Add('template_id', $TemplateId)
            }
            if ($PSBoundParameters.ContainsKey('Categories')) {
                $ContentBody.Add('categories', $Categories)
            }

            try {
                Remove-EmptyHashtable -Hashtable $ContentBody -Recursive
                $InvokeSplat.Add('ContentBody', $ContentBody)
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to send email via SendGrid API. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
