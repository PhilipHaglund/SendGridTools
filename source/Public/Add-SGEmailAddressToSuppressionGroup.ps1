function Add-SGEmailAddressToSuppressionGroup {
    <#
    .SYNOPSIS
        Adds email addresses to a suppression group.

    .DESCRIPTION
        The Add-SGEmailAddressToSuppressionGroup function adds email addresses to a suppression group in SendGrid.
        
    .PARAMETER GroupId
        Specifies the ID of the suppression group.

    .PARAMETER EmailAddresses
        Specifies the email addresses to add to the suppression group.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Add-SGEmailAddressToSuppressionGroup -GroupId 123 -EmailAddresses 'test@example.com'
        This command adds the email address 'test@example.com' to the suppression group with the ID 123.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    [Alias('Add-SGSuppression', 'Add-SGAddressToSuppression')]
    param (
        # Specifies the ID of the suppression group.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id')]
        [int]$GroupId,

        # Specifies the email addresses to add to the suppression group.
        [Parameter(
            Mandatory
        )]
        [MailAddress[]]$EmailAddresses,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = "asm/groups/$GroupId/suppressions"
            ContentBody   = @{ recipient_emails = $EmailAddresses | ForEach-Object { $_.Address } }
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
            $InvokeSplat.OnBehalfOf = $OnBehalfOf
        }
        if ($PSCmdlet.ShouldProcess(('Add email addresses to suppression group with ID {0}.' -f $GroupId))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to add email addresses to suppression group. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}