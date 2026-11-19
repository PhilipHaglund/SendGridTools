# Prompt-counting host for unit tests. Not a test file.
# ShouldProcess asks its question through the host, and -WhatIf writes its line through the host, so neither
# reaches a stream that a test can read, and a real host would wait on a console.
# Invoke-SgtInCountingHost runs a script in a second runspace whose host answers every choice prompt at once
# with the first choice (Yes), counts the prompts and records every line written to the host. No console is
# read, and any other kind of prompt throws. The network tripwire is enabled in that runspace before the
# module is imported there, and its record of unmocked calls comes back with the result.
#
# The script runs in the SendGridTools module scope of the second runspace, with no session, so a request
# stops at the connect-first error before any class method or transport call.

function Initialize-SgtCountingHostType {
    if ('SgtTest.CountingHost' -as [type]) {
        return
    }
    # C# 5 syntax only, so the Windows PowerShell 5.1 compiler accepts it.
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

namespace SgtTest
{
    public class CountingHostUI : PSHostUserInterface
    {
        private readonly List<string> _prompts = new List<string>();
        private readonly List<string> _lines = new List<string>();

        public List<string> Prompts { get { return _prompts; } }
        public List<string> Lines { get { return _lines; } }

        public override PSHostRawUserInterface RawUI { get { return null; } }

        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
        {
            _prompts.Add(caption + " | " + message);
            return 0;
        }

        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
        {
            throw new InvalidOperationException("The counting host answers choice prompts only: Prompt was called.");
        }

        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
        {
            throw new InvalidOperationException("The counting host answers choice prompts only: PromptForCredential was called.");
        }

        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
        {
            throw new InvalidOperationException("The counting host answers choice prompts only: PromptForCredential was called.");
        }

        public override string ReadLine()
        {
            throw new InvalidOperationException("The counting host answers choice prompts only: ReadLine was called.");
        }

        public override SecureString ReadLineAsSecureString()
        {
            throw new InvalidOperationException("The counting host answers choice prompts only: ReadLineAsSecureString was called.");
        }

        public override void Write(string value) { _lines.Add(value); }
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) { _lines.Add(value); }
        public override void WriteLine(string value) { _lines.Add(value); }
        public override void WriteErrorLine(string value) { _lines.Add(value); }
        public override void WriteDebugLine(string message) { _lines.Add(message); }
        public override void WriteVerboseLine(string message) { _lines.Add(message); }
        public override void WriteWarningLine(string message) { _lines.Add(message); }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
    }

    public class CountingHost : PSHost
    {
        private readonly Guid _instanceId = Guid.NewGuid();
        private readonly CountingHostUI _ui = new CountingHostUI();
        private readonly CultureInfo _culture = CultureInfo.CurrentCulture;
        private readonly CultureInfo _uiCulture = CultureInfo.CurrentUICulture;

        public CountingHostUI CountingUI { get { return _ui; } }

        public override string Name { get { return "SgtCountingHost"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override Guid InstanceId { get { return _instanceId; } }
        public override PSHostUserInterface UI { get { return _ui; } }
        public override CultureInfo CurrentCulture { get { return _culture; } }
        public override CultureInfo CurrentUICulture { get { return _uiCulture; } }

        public override void SetShouldExit(int exitCode) { }
        public override void EnterNestedPrompt() { throw new NotSupportedException("The counting host has no nested prompt."); }
        public override void ExitNestedPrompt() { throw new NotSupportedException("The counting host has no nested prompt."); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
}
'@
}

function Invoke-SgtInCountingHost {
    # Runs -Script (text) in the SendGridTools module scope of a second runspace with the counting host.
    # Returns PromptCount, Prompt, HostLine, Output, Threw, ThrownType, ThrownMessage, UnmockedCall and NetworkCallCount.
    param(
        [Parameter(Mandatory)][string]$Script
    )
    Initialize-SgtCountingHostType
    $Loaded = Get-Module -Name SendGridTools
    if (-not $Loaded) {
        throw 'Invoke-SgtInCountingHost needs SendGridTools imported in the calling runspace, to import the same built module.'
    }
    $ManifestPath = Join-Path -Path $Loaded.ModuleBase -ChildPath 'SendGridTools.psd1'
    $TripwirePath = Join-Path -Path $PSScriptRoot -ChildPath 'NetworkTripwire.ps1'

    $CountingHost = [SgtTest.CountingHost]::new()
    $Runspace = [runspacefactory]::CreateRunspace($CountingHost)
    $Shell = $null
    try {
        $Runspace.Open()
        $Shell = [powershell]::Create()
        $Shell.Runspace = $Runspace
        $null = $Shell.AddScript({
                param($TripwirePath, $ManifestPath, $Script)
                . $TripwirePath
                Enable-SgtNetworkTripwire
                Assert-SgtNetworkTripwireActive
                $Module = Import-Module -Name $ManifestPath -PassThru -ErrorAction Stop
                $Thrown = $null
                $Output = try { & $Module ([scriptblock]::Create($Script)) } catch { $Thrown = $_ }
                [pscustomobject]@{
                    Output           = @($Output)
                    Threw            = ($null -ne $Thrown)
                    ThrownType       = if ($Thrown) { $Thrown.Exception.GetType().FullName } else { $null }
                    ThrownMessage    = if ($Thrown) { [string]$Thrown.Exception.Message } else { $null }
                    UnmockedCall     = @(Get-SgtUnmockedNetworkCall)
                    NetworkCallCount = $global:SgtNetworkCall.Count
                }
            }).AddArgument($TripwirePath).AddArgument($ManifestPath).AddArgument($Script)
        $Inner = @($Shell.Invoke())
        if ($Shell.Streams.Error.Count -gt 0) {
            throw ('The counting-host runspace reported an error: {0}' -f $Shell.Streams.Error[0])
        }
        if ($Inner.Count -ne 1) {
            throw ('The counting-host runspace returned {0} objects, expected 1.' -f $Inner.Count)
        }
        [pscustomobject]@{
            PromptCount      = $CountingHost.CountingUI.Prompts.Count
            Prompt           = @($CountingHost.CountingUI.Prompts)
            HostLine         = @($CountingHost.CountingUI.Lines)
            Output           = @($Inner[0].Output)
            Threw            = [bool]$Inner[0].Threw
            ThrownType       = $Inner[0].ThrownType
            ThrownMessage    = $Inner[0].ThrownMessage
            UnmockedCall     = @($Inner[0].UnmockedCall)
            NetworkCallCount = [int]$Inner[0].NetworkCallCount
        }
    }
    finally {
        if ($Shell) { $Shell.Dispose() }
        $Runspace.Dispose()
    }
}
