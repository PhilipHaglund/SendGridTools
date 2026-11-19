# Child-process side of Invoke-SgtBootstrapInSandbox (BootstrapSandbox.ps1). Not a test file.
# Replaces every command that could change the machine, reach the network or change the list of repositories with a
# global function that records the call and throws, checks that each name resolves to that function, and only then
# runs the copy of Resolve-Dependency.ps1 in -SandboxPath. A few read-only commands are recorded and answer as the
# scenario says. The result goes to stdout as one marked line of serialised text.
#
# Microsoft.PowerShell.Archive\Expand-Archive is called module-qualified, which a function cannot replace. No
# scenario reaches it: the download fails, or the rename before it throws.
param(
    [Parameter(Mandatory)][string]$SandboxPath,
    [Parameter(Mandatory)][ValidateSet('NoPowerShellGet', 'PowerShellGetPresent', 'UnpackFails')][string]$Scenario
)

$global:SgtBootstrapCall = [System.Collections.Generic.List[string]]::new()
$global:SgtBootstrapScenario = $Scenario

$Throwing = @(
    'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer',
    'Install-PackageProvider', 'Import-PackageProvider', 'Register-PackageSource', 'Set-PackageSource', 'Unregister-PackageSource', 'Install-Package',
    'Install-Module', 'Save-Module', 'Update-Module', 'Install-Script', 'Save-Script',
    'Register-PSRepository', 'Set-PSRepository', 'Unregister-PSRepository',
    'Install-PSResource', 'Save-PSResource', 'Update-PSResource',
    'Register-PSResourceRepository', 'Set-PSResourceRepository', 'Unregister-PSResourceRepository',
    'Install-ModuleFast', 'Invoke-PSDepend',
    'Rename-Item', 'Remove-Item', 'Move-Item', 'Copy-Item', 'New-Item', 'Expand-Archive',
    'Set-ExecutionPolicy', 'Start-Process'
)
foreach ($Name in $Throwing) {
    $Body = @'
$null = $global:SgtBootstrapCall.Add('{0}')
if ('{0}' -eq 'Invoke-WebRequest' -and $global:SgtBootstrapScenario -eq 'UnpackFails') {{ return }}
throw 'Sandbox: {0} was reached and replaced.'
'@ -f $Name
    # Set-Item, since New-Item is itself among the names replaced here.
    Set-Item -Path ('Function:\global:{0}' -f $Name) -Value ([scriptblock]::Create($Body)) -Force
}

function global:Import-Module {
    $null = $global:SgtBootstrapCall.Add('Import-Module')
    if ($global:SgtBootstrapScenario -eq 'PowerShellGetPresent' -and @(@($args) | ForEach-Object { "$_" } | Where-Object { $_ -match 'PowerShellGet' }).Count -gt 0) {
        [pscustomobject]@{ Name = 'PowerShellGet'; Version = [version]'2.2.5' }
    }
}
function global:Get-PackageProvider {
    $null = $global:SgtBootstrapCall.Add('Get-PackageProvider')
    if ($global:SgtBootstrapScenario -eq 'PowerShellGetPresent') {
        [pscustomobject]@{ Name = 'NuGet'; Version = [version]'2.8.5.208' }
    }
}
function global:Get-PSRepository {
    $null = $global:SgtBootstrapCall.Add('Get-PSRepository')
    [pscustomobject]@{ Name = 'PSGallery'; Trusted = $false; InstallationPolicy = 'Untrusted' }
}
function global:Get-PSResourceRepository {
    $null = $global:SgtBootstrapCall.Add('Get-PSResourceRepository')
    [pscustomobject]@{ Name = 'PSGallery'; Trusted = $false }
}
function global:Start-Sleep {
    $null = $global:SgtBootstrapCall.Add('Start-Sleep')
}

# An alias outranks a function, so check what each name resolves to before anything runs.
$Expected = $Throwing + @('Import-Module', 'Get-PackageProvider', 'Get-PSRepository', 'Get-PSResourceRepository', 'Start-Sleep')
foreach ($Name in $Expected) {
    $Found = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $Found -or $Found.CommandType -ne 'Function' -or -not $Found.ScriptBlock.ToString().Contains('SgtBootstrapCall')) {
        [Console]::Out.WriteLine(('Sandbox not in place: {0} resolves to {1}. Nothing was run.' -f $Name, $(if ($Found) { $Found.CommandType } else { 'nothing' })))
        exit 3
    }
}

$Result = @{ Call = $null; Threw = $false; ThrownType = ''; ThrownMessage = ''; InnerType = ''; Warning = @() }
$ScriptCopy = Join-Path -Path $SandboxPath -ChildPath 'Resolve-Dependency.ps1'
Push-Location -LiteralPath $SandboxPath
try {
    $Warnings = $null
    & $ScriptCopy -WarningVariable Warnings -WarningAction SilentlyContinue *> $null
    $Result.Warning = @($Warnings | ForEach-Object { "$_" })
}
catch {
    $Result.Threw = $true
    $Result.ThrownType = $_.Exception.GetType().FullName
    $Result.ThrownMessage = "$($_.Exception.Message)"
    $Result.InnerType = if ($_.Exception.InnerException) { $_.Exception.InnerException.GetType().FullName } else { '' }
    $Result.Warning = @($Warnings | ForEach-Object { "$_" })
}
finally {
    Pop-Location
}
$Result.Call = $global:SgtBootstrapCall.ToArray()

$Serialised = [System.Management.Automation.PSSerializer]::Serialize($Result)
[Console]::Out.WriteLine('SGT-BOOTSTRAP-SANDBOX-RESULT:' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Serialised)))
exit 0
