function Add-SGGlobalSuppression {
    <#
    .SYNOPSIS
        Adds a specific email address to the global suppressions list in SendGrid.

    .DESCRIPTION
        The Add-SGGlobalSuppression function adds a specific email address to the global suppressions list in SendGrid.

    .PARAMETER EmailAddress
        Specifies the email address to add to the global suppressions list.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's sub users or customer accounts.

    .EXAMPLE
        PS C:\> Add-SGSGlobalSuppression -EmailAddress 'test@example.com'
        This command add the email address 'test@example.com' to the global suppressions list in SendGrid.

    .EXAMPLE
        PS C:\> Add-SGSGlobalSuppression -EmailAddress 'test@example.com' -OnBehalfOf 'Subuser'
        This command add the email address 'test@example.com' to the global suppressions list in SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess
    )]
    param (
        # Specifies the email address to remove from the global suppressions list.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's sub users or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = "suppression/unsubscribes"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        foreach ($Email in $EmailAddress) {
            $InvokeSplat['ContentBody'] = @{
                'emails' = @(@{email = $Email.Address})
            }
            if ($PSCmdlet.ShouldProcess(('Add email address {0} to the global suppressions list.' -f $Email.Address))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to add email address "{0}" to the global suppressions list. {0}' -f $Email.Address, $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
