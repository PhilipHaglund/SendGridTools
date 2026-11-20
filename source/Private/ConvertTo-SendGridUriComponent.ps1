<#
.SYNOPSIS
Encodes a text for one part of a SendGrid request address, the same way in PowerShell 7 and Windows PowerShell 5.1.

.DESCRIPTION
Returns [uri]::EscapeDataString of the value and then encodes !, *, ', ( and ) as %21, %2A, %27, %28 and %29.
PowerShell 7 already encodes these five characters, so there the result equals [uri]::EscapeDataString character for
character; Windows PowerShell 5.1 leaves them as they are, so there the result now equals the one in PowerShell 7.
$null and an empty text give an empty text, as [uri]::EscapeDataString does when PowerShell calls it.

.PARAMETER Value
The text to encode, for example an id for a path segment or a value in the query.

.EXAMPLE
ConvertTo-SendGridUriComponent 'a/b!c'

Returns a%2Fb%21c in both shells.
#>
function ConvertTo-SendGridUriComponent {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The text to encode.
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Value
    )
    [uri]::EscapeDataString($Value).Replace('!', '%21').Replace('*', '%2A').Replace("'", '%27').Replace('(', '%28').Replace(')', '%29')
}
