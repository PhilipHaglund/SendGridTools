# Prompt-counting host for unit tests. Not a test file.
# ShouldProcess asks its question through the host, and -WhatIf writes its line through the host, so neither
# reaches a stream that a test can read, and a real host would wait on a console.
# Invoke-SgtInCountingHost runs a script in a host that answers every choice prompt at once with the first
# choice (Yes), counts the prompts and records every line written to the host. No console is read, and any
# other kind of prompt throws.
#
# The host lives in a new process of the running shell (PromptCountingHostChild.ps1), started with
# -NonInteractive. A second import of the module inside the test process is avoided on purpose: in Windows
# PowerShell 5.1 it moves the static methods of the module's classes to the new runspace, and they fail in
# every later test once that runspace is gone (measured). The network tripwire is enabled in the child before
# the module is imported there, and its record of unmocked calls comes back with the result.
#
# The script runs in the SendGridTools module scope of the child, with no session, so a request stops at the
# connect-first error before any class method or transport call.

function Invoke-SgtInCountingHost {
    # Runs -Script (text) in the SendGridTools module scope of a child process with the counting host.
    # Returns PromptCount, Prompt, HostLine, Output, Threw, ThrownType, ThrownMessage, UnmockedCall and NetworkCallCount.
    param(
        [Parameter(Mandatory)][string]$Script
    )
    $Loaded = Get-Module -Name SendGridTools
    if (-not $Loaded) {
        throw 'Invoke-SgtInCountingHost needs SendGridTools imported in the calling runspace, to run the same built module.'
    }
    $ManifestPath = Join-Path -Path $Loaded.ModuleBase -ChildPath 'SendGridTools.psd1'
    $TripwirePath = Join-Path -Path $PSScriptRoot -ChildPath 'NetworkTripwire.ps1'
    $ChildPath = Join-Path -Path $PSScriptRoot -ChildPath 'PromptCountingHostChild.ps1'

    # The same shell as the one that runs the test. Windows PowerShell 5.1 has no $IsWindows, so test the edition and $env:OS.
    $ShellName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } elseif ($env:OS -eq 'Windows_NT') { 'pwsh.exe' } else { 'pwsh' }
    $ShellPath = Join-Path -Path $PSHOME -ChildPath $ShellName
    $ScriptBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Script))

    # A stderr line from the child under 2>&1 must not become a terminating error under a caller with Stop.
    $ErrorActionPreference = 'Continue'
    $ChildOutput = @(& $ShellPath -NoProfile -NonInteractive -File $ChildPath -TripwirePath $TripwirePath -ManifestPath $ManifestPath -ScriptBase64 $ScriptBase64 2>&1 | ForEach-Object -Process { "$_" })
    $ExitCode = $LASTEXITCODE
    $Marker = 'SGT-COUNTING-HOST-RESULT:'
    $ResultLine = @($ChildOutput | Where-Object -FilterScript { $_.StartsWith($Marker) })
    if ($ExitCode -ne 0 -or $ResultLine.Count -ne 1) {
        throw ('The counting-host process gave no result (exit code {0}). Its output: {1}' -f $ExitCode, ($ChildOutput -join "`n"))
    }
    $Serialised = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ResultLine[0].Substring($Marker.Length)))
    $Result = [System.Management.Automation.PSSerializer]::Deserialize($Serialised)
    [pscustomobject]@{
        PromptCount      = @($Result.Prompt).Count
        Prompt           = [string[]]@($Result.Prompt)
        HostLine         = [string[]]@($Result.HostLine)
        Output           = [string[]]@($Result.Output)
        Threw            = [bool]$Result.Threw
        ThrownType       = [string]$Result.ThrownType
        ThrownMessage    = [string]$Result.ThrownMessage
        UnmockedCall     = [string[]]@($Result.UnmockedCall)
        NetworkCallCount = [int]$Result.NetworkCallCount
    }
}
