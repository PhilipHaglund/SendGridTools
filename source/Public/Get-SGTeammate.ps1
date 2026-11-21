function Get-SGTeammate {
    <#
    .SYNOPSIS
        Retrieves all or a specific Teammate from SendGrid.

    .DESCRIPTION
        Get-SGTeammate retrieves all or a specific Teammate from SendGrid. You can specify the specific username to retrieve.
        Without -Username every page is read, so all teammates are returned.

    .PARAMETER Username
        Specifies the specific username to retrieve. An empty value is refused.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGTeammate

        This command retrieves all teammates from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGTeammate -Username name@example.com

        This command retrieves the specific teammate with the username'name@example.com' from SendGrid.
    #>
    [CmdletBinding()]
    param (
        # Specifies the specific username to retrieve. An empty value is refused.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [string[]]$Username,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = "teammates"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        if ($PSBoundParameters.ContainsKey('Username')) {
            foreach ($User in $Username) {
                $UserInvokeSplat = $InvokeSplat.Clone()
                $UserInvokeSplat['Namespace'] = "teammates/$((ConvertTo-SendGridUriComponent $User))"
                try {
                    Invoke-SendGrid @UserInvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve SendGrid teammate. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
        else {
            try {
                Invoke-SendGridPagedList -InvokeSplat $InvokeSplat -IdProperty 'Username'
            }
            catch {
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve all SendGrid teammates. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}