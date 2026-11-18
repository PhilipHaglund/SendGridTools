<#
.SYNOPSIS
Tells whether the PowerShell host can ask the user a question.

.DESCRIPTION
Test-SendGridHostCanPrompt returns $true in a remote session (the host is 'ServerRemoteHost', for example Enter-PSSession), whatever the process
looks like, because a remote session leaves the prompt to the client. Otherwise it returns $false when the host cannot prompt: the process is not user interactive (a Windows service or a
scheduled task that runs whether or not the user is signed in), the host is the 'Default Host' (a runspace without a user interface, for
example a hosted automation runbook), or the host was started with -NonInteractive or a prefix of it with at least four letters. Only
the host's own switches are read, up to the first argument that is not a switch or that starts the command, so a -NonInteractive that
belongs to a script's arguments does not count. The value of a switch that takes one (for example -ExecutionPolicy Bypass, -WindowStyle
Hidden, -InputFormat Text or -WorkingDirectory) is skipped and does not end the scan. Otherwise it returns $true.

.PARAMETER CommandLineArgs
The command line of the process, the program name first. Defaults to the command line of the current process.

.PARAMETER UserInteractive
Whether the process is user interactive. Defaults to [Environment]::UserInteractive.

.PARAMETER HostName
The name of the PowerShell host. Defaults to the name of the current host.

.EXAMPLE
Test-SendGridHostCanPrompt

Returns $true in an interactive console and $false in a host that was started with -NonInteractive.

#>
function Test-SendGridHostCanPrompt {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [string[]]$CommandLineArgs = [Environment]::GetCommandLineArgs(),

        [bool]$UserInteractive = [Environment]::UserInteractive,

        [string]$HostName = $Host.Name
    )

    # A remote session (Enter-PSSession): Get-Credential is relayed to the client's host, so the client decides.
    if ($HostName -eq 'ServerRemoteHost') {
        return $true
    }

    if (-not $UserInteractive -or $HostName -eq 'Default Host') {
        return $false
    }

    # The switches that start the command or name the script end the host's own switches.
    $Stops = 'command', 'file', 'encodedcommand', 'commandwithargs'
    # The switches that take a value: the value is skipped, it does not end the scan.
    $ValueAliases = 'ep', 'ex', 'w', 'wd', 'if', 'of', 'o', 'v', 'config', 'settings'
    $ValueSwitches = 'executionpolicy', 'windowstyle', 'workingdirectory', 'inputformat', 'outputformat', 'version', 'configurationname', 'configurationfile', 'settingsfile', 'custompipename', 'psconsolefile'
    $Skip = $false
    foreach ($Argument in @($CommandLineArgs | Select-Object -Skip 1)) {
        if ($Skip) {
            $Skip = $false
            continue
        }
        if ($Argument -notmatch '^(?:-{1,2}|/)([A-Za-z]+)$') {
            break
        }
        $Name = $Matches[1].ToLowerInvariant()
        if ($Name -in 'ec', 'cwa' -or @($Stops | Where-Object { $_.StartsWith($Name) }).Count -gt 0) {
            break
        }
        if ($Name.Length -ge 4 -and 'noninteractive'.StartsWith($Name)) {
            return $false
        }
        if ($Name -in $ValueAliases -or ($Name.Length -ge 3 -and @($ValueSwitches | Where-Object { $_.StartsWith($Name) }).Count -gt 0)) {
            $Skip = $true
        }
    }
    $true
}
