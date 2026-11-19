# Bootstrap sandbox for unit tests. Not a test file.
# Invoke-SgtBootstrapInSandbox runs a copy of Resolve-Dependency.ps1 (with a copy of Resolve-Dependency.psd1 beside
# it) in a new process of the running shell, started with -NoProfile and -NonInteractive. Before the script starts,
# the child (BootstrapSandboxChild.ps1) replaces every command that could change the machine, reach the network or
# change the list of repositories with a function that records the call and throws. A few read-only commands are
# recorded too and answer as the scenario says, so a run reaches the same branches on every machine. The child
# checks that each name resolves to its replacement and runs nothing when one does not.
#
# Scenarios (the PSResourceGet download is the script's first call that reaches out):
#   NoPowerShellGet       the download fails; PowerShellGet 2.x cannot be imported and no NuGet provider is listed.
#   PowerShellGetPresent  the download fails; PowerShellGet 2.x imports and a NuGet provider is listed.
#   UnpackFails           the download succeeds (the replacement writes nothing) and the first unpack step fails.
#
# The script and its configuration are copied into -SandboxPath (a TestDrive folder), so $PSScriptRoot and the
# default output folder of the script lie there. The result comes back as one marked line of serialised text.

function Invoke-SgtBootstrapInSandbox {
    # Returns Call (the recorded command names, in order), Threw, ThrownType, ThrownMessage, InnerType and Warning.
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$SandboxPath,
        [Parameter(Mandatory)][ValidateSet('NoPowerShellGet', 'PowerShellGetPresent', 'UnpackFails')][string]$Scenario
    )
    $null = New-Item -Path $SandboxPath -ItemType Directory -Force
    Copy-Item -LiteralPath $ScriptPath -Destination (Join-Path -Path $SandboxPath -ChildPath 'Resolve-Dependency.ps1') -Force
    Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path -Path $SandboxPath -ChildPath 'Resolve-Dependency.psd1') -Force
    $ChildPath = Join-Path -Path $PSScriptRoot -ChildPath 'BootstrapSandboxChild.ps1'

    # The same shell as the one that runs the test. Windows PowerShell 5.1 has no $IsWindows, so test the edition and $env:OS.
    $ShellName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } elseif ($env:OS -eq 'Windows_NT') { 'pwsh.exe' } else { 'pwsh' }
    $ShellPath = Join-Path -Path $PSHOME -ChildPath $ShellName
    $ChildArguments = @('-NoProfile', '-NonInteractive', '-File', $ChildPath, '-SandboxPath', (Convert-Path -LiteralPath $SandboxPath), '-Scenario', $Scenario)

    # A stderr line from the child under 2>&1 must not become a terminating error under a caller with Stop.
    $ErrorActionPreference = 'Continue'
    $ChildOutput = @(& $ShellPath @ChildArguments 2>&1 | ForEach-Object -Process { "$_" })
    $ExitCode = $LASTEXITCODE
    $Marker = 'SGT-BOOTSTRAP-SANDBOX-RESULT:'
    $ResultLine = @($ChildOutput | Where-Object -FilterScript { $_.StartsWith($Marker) })
    if ($ExitCode -ne 0 -or $ResultLine.Count -ne 1) {
        throw ('The bootstrap sandbox process gave no result (exit code {0}). Its output: {1}' -f $ExitCode, ($ChildOutput -join "`n"))
    }
    $Serialised = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ResultLine[0].Substring($Marker.Length)))
    $Result = [System.Management.Automation.PSSerializer]::Deserialize($Serialised)
    [pscustomobject]@{
        Call          = [string[]]@($Result.Call)
        Threw         = [bool]$Result.Threw
        ThrownType    = [string]$Result.ThrownType
        ThrownMessage = [string]$Result.ThrownMessage
        InnerType     = [string]$Result.InnerType
        Warning       = [string[]]@($Result.Warning)
    }
}

# The commands the sandbox records and answers without throwing; every other recorded name is a replacement that throws.
$script:SgtBootstrapReadOnlyCommand = @('Import-Module', 'Get-PackageProvider', 'Get-PSRepository', 'Get-PSResourceRepository', 'Start-Sleep')

# Commands of the legacy PowerShellGet path: PowerShellGet itself, the NuGet provider and the repository settings.
$script:SgtBootstrapLegacyCommand = @(
    'Import-Module', 'Get-PackageProvider', 'Install-PackageProvider', 'Import-PackageProvider',
    'Get-PSRepository', 'Set-PSRepository', 'Register-PSRepository', 'Unregister-PSRepository',
    'Install-Module', 'Save-Module', 'Invoke-PSDepend'
)
