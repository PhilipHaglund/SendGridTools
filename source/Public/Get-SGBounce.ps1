function Get-SGBounce {
    <#
    .SYNOPSIS
        Retrieves all or specific bounces from SendGrid.

    .DESCRIPTION
        Get-SGBounce retrieves all bounces or a specific bounce based on its unique ID from SendGrid. Bounces occur when an email is rejected by the recipient's mail server.

    .PARAMETER UniqueId
        Specifies the UniqueId of a specific bounce to retrieve. If this parameter is not provided, all bounces are retrieved.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGBounce

        Email             : bounce1@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2022-03-04 15:34:34
        Updated           : 2022-03-04 15:34:34
        UniqueId          : 13508031
        UserId            : 8262273

        Email             : bounce2@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        UniqueId          : 12589712
        UserId            : 8262273
        ...

        This command retrieves all bounces from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBounce -UniqueId 12589712

        Email             : bounce2@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        UniqueId          : 12589712
        UserId            : 8262273

        This command retrieves the bounce with the UniqueId '12589712' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBounce -UniqueId 12589712 -OnBehalfOf 'Subuser'

        Email             : bounce2@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        UniqueId          : 12589712
        UserId            : 8262273
        Username          : Subuser

        This command retrieves the bounce with the UniqueId '12589712' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the specific email address to retrieve. If this parameter is not provided, all bounces are retrieved.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [MailAddress[]]$EmailAddress,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'suppression/bounces'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSBoundParameters.EmailAddress) {
            foreach ($Id in $EmailAddress) {
                if ($PSCmdlet.ShouldProcess(('{0}' -f $Id))) {
                    $InvokeSplat['Namespace'] = "suppression/bounces/$Id"
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to retrieve SendGrid bounce. {0}' -f $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess(('All bounces'))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve all SendGrid bounces. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }   
}