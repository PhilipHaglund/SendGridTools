BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/BootstrapSandbox.ps1')
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
}

AfterAll {
    Disable-SgtNetworkTripwire
}

# Sprint 4 step 4 measurement (D40). Each It runs the repository's Resolve-Dependency.ps1 in a sandbox process
# (BootstrapSandbox.ps1) and writes one MEASURE line with command names, counts and True/False only. It asserts
# nothing about the measured value, so the same file measures any version of the script.
Describe 'Sprint 4 step 4 measurements' {
    It 'D40: the commands the bootstrap reaches when <Scenario>' -ForEach @(
        @{ Scenario = 'NoPowerShellGet'; Text = 'the PSResourceGet download fails, without PowerShellGet 2.x or a NuGet provider' }
        @{ Scenario = 'PowerShellGetPresent'; Text = 'the PSResourceGet download fails, with PowerShellGet 2.x and a NuGet provider' }
        @{ Scenario = 'UnpackFails'; Text = 'the PSResourceGet download succeeds and the unpack fails' }
    ) {
        $Run = Invoke-SgtBootstrapInSandbox -Scenario $Scenario -SandboxPath (Join-Path -Path 'TestDrive:\' -ChildPath $Scenario) `
            -ScriptPath (Join-Path -Path $script:ProjectPath -ChildPath 'Resolve-Dependency.ps1') `
            -ConfigPath (Join-Path -Path $script:ProjectPath -ChildPath 'Resolve-Dependency.psd1')
        $Legacy = @($Run.Call | Where-Object { $_ -in $script:SgtBootstrapLegacyCommand })
        $Result = 'calls {0}: {1}; legacy PowerShellGet, NuGet provider or repository commands {2}: {3}; reaches Install-PackageProvider {4}; reaches Set-PSRepository {5}; warnings {6}; a warning says Reverting to PowerShellGet {7}; threw {8}; the error names Microsoft.PowerShell.PSResourceGet {9}; inner exception {10}' -f `
            $Run.Call.Count, ($Run.Call -join ','), $Legacy.Count, ($Legacy -join ','), ($Run.Call -contains 'Install-PackageProvider'), ($Run.Call -contains 'Set-PSRepository'),
            $Run.Warning.Count, (@($Run.Warning | Where-Object { $_ -like '*Reverting to PowerShellGet*' }).Count -gt 0), $Run.Threw,
            ($Run.ThrownMessage -like '*Microsoft.PowerShell.PSResourceGet*'), ($Run.InnerType -ne '')
        Write-Host ('MEASURE D40 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Text, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
