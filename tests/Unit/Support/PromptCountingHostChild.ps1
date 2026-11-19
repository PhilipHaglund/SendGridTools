# Child-process side of Invoke-SgtInCountingHost (PromptCountingHost.ps1). Not a test file.
# Runs one script in the SendGridTools module scope of a runspace whose host answers every choice prompt at
# once with the first choice (Yes), counts the prompts and records every line written to the host. No console
# is read, and any other kind of prompt throws. The network tripwire is enabled in that runspace before the
# module is imported there. The result goes to stdout as one marked line of serialised text.
#
# This process imports the module in that one runspace only, and nowhere else.
param(
    [Parameter(Mandatory)][string]$TripwirePath,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ScriptBase64
)
$ErrorActionPreference = 'Stop'

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

$Script = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ScriptBase64))
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
                Output           = [string[]]@($Output | ForEach-Object { "$_" })
                Threw            = ($null -ne $Thrown)
                ThrownType       = if ($Thrown) { $Thrown.Exception.GetType().FullName } else { '' }
                ThrownMessage    = if ($Thrown) { [string]$Thrown.Exception.Message } else { '' }
                UnmockedCall     = [string[]]@(Get-SgtUnmockedNetworkCall)
                NetworkCallCount = [int]$global:SgtNetworkCall.Count
            }
        }).AddArgument($TripwirePath).AddArgument($ManifestPath).AddArgument($Script)
    $Inner = @($Shell.Invoke())
    if ($Shell.Streams.Error.Count -gt 0) {
        throw ('The counting-host runspace reported an error: {0}' -f $Shell.Streams.Error[0])
    }
    if ($Inner.Count -ne 1) {
        throw ('The counting-host runspace returned {0} objects, expected 1.' -f $Inner.Count)
    }
    $Result = [pscustomobject]@{
        Prompt           = [string[]]@($CountingHost.CountingUI.Prompts)
        HostLine         = [string[]]@($CountingHost.CountingUI.Lines)
        Output           = [string[]]@($Inner[0].Output)
        Threw            = [bool]$Inner[0].Threw
        ThrownType       = [string]$Inner[0].ThrownType
        ThrownMessage    = [string]$Inner[0].ThrownMessage
        UnmockedCall     = [string[]]@($Inner[0].UnmockedCall)
        NetworkCallCount = [int]$Inner[0].NetworkCallCount
    }
    $Serialised = [System.Management.Automation.PSSerializer]::Serialize($Result, 3)
    'SGT-COUNTING-HOST-RESULT:' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Serialised))
}
finally {
    if ($Shell) { $Shell.Dispose() }
    $Runspace.Dispose()
}
