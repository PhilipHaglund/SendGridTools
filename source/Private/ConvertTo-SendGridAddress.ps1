function ConvertTo-SendGridAddress {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [Alias("EmailAddress")]
        [object[]]$Address
    )
    process {
        foreach ($A in $Address) {
            try {
                $EmailAddress = [System.Net.Mail.MailAddress]$A
                if ($null -eq $EmailAddress.DisplayName -or $EmailAddress.DisplayName -eq [string]::Empty) {
                    @{
                        email = $EmailAddress.Address
                    }
                }
                else {
                    @{
                        email = $EmailAddress.Address
                        name  = $EmailAddress.DisplayName
                    }
                }
            }
            catch {
                Write-Error "Invalid email address: $A" -ErrorAction Stop
            }
        }
    }
}