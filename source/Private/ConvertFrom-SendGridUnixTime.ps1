function ConvertFrom-SendGridUnixTime {
    <#
    .SYNOPSIS
        Turns Unix seconds under a time name into a date, only when every number fits Int32.

    .DESCRIPTION
        ConvertFrom-SendGridUnixTime applies one rule for time values to a property SendGrid sent. When the name
        holds valid, created, updated, lastat or ends in _at, the value is not null, and every element of the value
        (at least one) is an Int32 or Int64 within the Int32 range, the value becomes a date, or a list of dates in
        the same order when the value is a list. Every other value is returned unchanged. The result is an object
        with Converted (true when dates were made) and Value, so a list stays a list.

    .PARAMETER Name
        The property name as SendGrid sends it, for example added_at.

    .PARAMETER Value
        The value as SendGrid sends it.

    .EXAMPLE
        (ConvertFrom-SendGridUnixTime -Name 'added_at' -Value 1700000000).Value

        Returns the date 2023-11-14 22:13:20.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The property name as SendGrid sends it, for example added_at.
        [Parameter(Mandatory)]
        [string]$Name,

        # The value as SendGrid sends it.
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Value
    )
    if ($Name -match 'valid|created|updated|lastat|_at$' -and $null -ne $Value) {
        $Items = @($Value)
        $Fits = $Items.Count -gt 0
        foreach ($Item in $Items) {
            if (-not (($Item -is [int] -or $Item -is [int64]) -and $Item -ge [int]::MinValue -and $Item -le [int]::MaxValue)) {
                $Fits = $false
                break
            }
        }
        if ($Fits) {
            if ($Value -is [array]) {
                $Dates = [object[]]@($Items | ForEach-Object { [UnixTime]::FromUnixTime([int]$_) })
                return [pscustomobject]@{ Converted = $true; Value = $Dates }
            }
            return [pscustomobject]@{ Converted = $true; Value = [UnixTime]::FromUnixTime([int]$Value) }
        }
    }
    [pscustomobject]@{ Converted = $false; Value = $Value }
}
