<#
.SYNOPSIS
Builds the exception a command writes when a SendGrid call fails, with the caught exception as its cause.

.DESCRIPTION
ConvertTo-SendGridCommandException returns a WriteErrorException (the type Write-Error gives for a text) whose message is the text the
command writes and whose InnerException is the exception the command caught. StatusCode and SendGridErrors are copied into its Data from
the first exception in the chain of the caught exception, through InnerException, that holds the key. It never throws. A command passes
the result to Write-Error -Exception, so the error id, the category and the way the error stops stay those of Write-Error.

.PARAMETER Message
The text of the error, as the command wrote it before.

.PARAMETER ErrorRecord
The error record the command caught, normally $_ in its catch block.

.EXAMPLE
Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to do a thing. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop

Writes the error with the text of the command, the caught exception as its cause and the HTTP status and SendGrid errors in its Data.

#>
function ConvertTo-SendGridCommandException {
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.WriteErrorException])]
    param (
        # The text of the error, as the command wrote it before.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        # The error record the command caught, normally $_ in its catch block.
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Caught = $ErrorRecord.Exception
    $Result = [Microsoft.PowerShell.Commands.WriteErrorException]::new($Message, $Caught)
    try {
        foreach ($Key in 'StatusCode', 'SendGridErrors') {
            $Current = $Caught
            $Seen = 0
            # The depth limit keeps a cyclic chain from looping.
            while ($null -ne $Current -and $Seen -lt 32) {
                if ($Current.Data.Contains($Key)) {
                    $Result.Data[$Key] = $Current.Data[$Key]
                    break
                }
                $Current = $Current.InnerException
                $Seen++
            }
        }
    }
    catch {
        # Reading the cause must never hide the error itself.
        $null = $_
    }
    $Result
}
