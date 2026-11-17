<#
.SYNOPSIS
Resolves the SendGrid API base URI for a region or for an explicit address.

.DESCRIPTION
Resolve-SendGridBaseUri returns the absolute base URI that the SendGrid session sends its requests to. Without parameters, or with
-Region Global, it returns the global host. With -Region EU it returns the EU host. -BaseUri overrides the region: it must be an
absolute https address without user information, query or fragment, and '/v3' is appended when its path does not already end with it.
A trailing slash is removed. An address that does not meet these rules raises a terminating error.

.PARAMETER Region
The SendGrid region to resolve, Global or EU. Global is the default. It is ignored when BaseUri is given.

.PARAMETER BaseUri
An explicit base URI to use instead of a region. Only https is accepted, and '/v3' is appended when the path does not end with it.

.EXAMPLE
Resolve-SendGridBaseUri -Region EU

Returns https://api.eu.sendgrid.com/v3.

.EXAMPLE
Resolve-SendGridBaseUri -BaseUri 'https://proxy.example.com/sendgrid'

Returns https://proxy.example.com/sendgrid/v3.

#>
function Resolve-SendGridBaseUri {
    [CmdletBinding()]
    [OutputType([System.Uri])]
    param (
        # The SendGrid region, Global or EU.
        [Parameter()]
        [ValidateSet('Global', 'EU')]
        [string]$Region = 'Global',

        # An explicit base URI that overrides the region.
        [Parameter()]
        [uri]$BaseUri
    )

    process {
        if (-not $PSBoundParameters.ContainsKey('BaseUri') -or $null -eq $BaseUri) {
            if ($Region -eq 'EU') {
                return [uri]'https://api.eu.sendgrid.com/v3'
            }
            return [uri]'https://api.sendgrid.com/v3'
        }

        $Parsed = $null
        $Text = $BaseUri.OriginalString
        if (-not [uri]::TryCreate($Text, [UriKind]::Absolute, [ref]$Parsed)) {
            throw ('The base URI ''{0}'' is not an absolute URI.' -f $Text)
        }
        if ($Parsed.Scheme -ne 'https') {
            throw ('The base URI ''{0}'' must use https.' -f $Text)
        }
        if ($Parsed.UserInfo) {
            throw 'The base URI must not contain user information.'
        }
        if ($Parsed.Query -or $Parsed.Fragment) {
            throw 'The base URI must not contain a query or a fragment.'
        }

        $Path = $Parsed.AbsolutePath.TrimEnd('/')
        if ($Path -notmatch '(?i)/v3$') {
            $Path = $Path + '/v3'
        }
        [uri]($Parsed.GetLeftPart([System.UriPartial]::Authority) + $Path)
    }
}
