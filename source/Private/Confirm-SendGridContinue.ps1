<#
.SYNOPSIS
Asks the user to continue, through the ShouldContinue method of the calling cmdlet.

.DESCRIPTION
Confirm-SendGridContinue calls ShouldContinue on the given cmdlet with the given query and caption, and returns its answer. It exists so that
unit tests can mock the question; the question and its answer are exactly those of ShouldContinue.

.PARAMETER Cmdlet
The $PSCmdlet of the calling advanced function.

.PARAMETER Query
The query of the question, the first argument of ShouldContinue.

.PARAMETER Caption
The caption of the question, the second argument of ShouldContinue.

.EXAMPLE
Confirm-SendGridContinue -Cmdlet $PSCmdlet -Query 'example.com' -Caption 'Do you want to continue?'

Asks the question and returns $true when the user answers yes.
#>
function Confirm-SendGridContinue {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        $Cmdlet,

        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string]$Caption
    )
    $Cmdlet.ShouldContinue($Query, $Caption)
}
