function Remove-SGGlobalSuppression {
    <#
    .SYNOPSIS
        Removes a specific email address from the global suppressions list in SendGrid.

    .DESCRIPTION
        Remove-SGGlobalSuppression removes a specific email address from the global suppressions list in SendGrid.

    .PARAMETER EmailAddress
        Specifies the email address to remove from the global suppressions list.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER InputObject
        Hidden parameter that accepts email addresses, or objects with an Email property, from the pipeline. One request is sent for each item.

    .EXAMPLE
        PS C:\> Remove-SGGlobalSuppression -EmailAddress 'test@example.com'
        This command removes the email address 'test@example.com' from the global suppressions list in SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGGlobalSuppression -EmailAddress 'test@example.com' -OnBehalfOf 'Subuser'
        This command removes the email address 'test@example.com' from the global suppressions list in SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High',
        DefaultParameterSetName = 'Default'
    )]
    param (
        # Specifies the email address to remove from the global suppressions list.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,

        # Specifies the email address to remove from the global suppressions list.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'InputObject')]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $AddressList = [System.Collections.Generic.List[string]]::new()
            foreach ($Object in $InputObject) {
                $Candidate = if ($null -ne $Object -and $Object.PSObject.Properties['Email']) {
                    $Object.Email
                }
                elseif ($Object -is [MailAddress]) {
                    $Object.Address
                }
                else {
                    $Object
                }
                try {
                    $AddressList.Add(([MailAddress]::new("$Candidate")).Address)
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to convert InputObject to an email address.') -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
        else {
            $AddressList = @($EmailAddress | ForEach-Object { $_.Address })
        }
        foreach ($Id in $AddressList) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "suppression/unsubscribes/$([uri]::EscapeDataString($Id))"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess(('Remove email address {0} from global suppressions list.' -f $Id))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to remove email address "{0}" from global suppressions list. {1}' -f $Id, $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
    }
}
