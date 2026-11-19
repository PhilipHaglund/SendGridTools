BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/BootstrapSandbox.ps1')
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path

    function Invoke-SgtBootstrapCase {
        param([string]$Scenario)
        Invoke-SgtBootstrapInSandbox -Scenario $Scenario -SandboxPath (Join-Path -Path 'TestDrive:\' -ChildPath $Scenario) `
            -ScriptPath (Join-Path -Path $script:ProjectPath -ChildPath 'Resolve-Dependency.ps1') `
            -ConfigPath (Join-Path -Path $script:ProjectPath -ChildPath 'Resolve-Dependency.psd1')
    }
}

AfterAll {
    Disable-SgtNetworkTripwire
}

# SGT-37 (D40): with UsePSResourceGet, a failed download or unpack of PSResourceGet stops the bootstrap with an error
# that names the module and the cause. It never reaches PowerShellGet, the NuGet provider or a repository setting.
# The script runs only in the sandbox process of BootstrapSandbox.ps1, where those commands record and throw.
Describe 'Resolve-Dependency.ps1 when PSResourceGet cannot be bootstrapped' {
    It 'stops with an error naming the module and the cause when the download fails (<Scenario>)' -ForEach @(
        @{ Scenario = 'NoPowerShellGet' }
        @{ Scenario = 'PowerShellGetPresent' }
    ) {
        $Run = Invoke-SgtBootstrapCase -Scenario $Scenario

        $Run.Threw | Should -BeTrue
        $Run.ThrownType | Should -Be 'System.InvalidOperationException'
        $Run.ThrownMessage | Should -BeLike '*Microsoft.PowerShell.PSResourceGet*'
        $Run.ThrownMessage | Should -BeLike '*download*'
        $Run.ThrownMessage | Should -BeLike '*Sandbox: Invoke-WebRequest was reached and replaced.*'
        $Run.InnerType | Should -Not -BeNullOrEmpty
        ($Run.Call -join ',') | Should -Be 'Invoke-WebRequest'
        @($Run.Call | Where-Object { $_ -in $script:SgtBootstrapLegacyCommand }) | Should -BeNullOrEmpty
        @($Run.Warning | Where-Object { $_ -like '*Reverting to PowerShellGet*' }) | Should -BeNullOrEmpty
    }

    It 'stops with an error naming the module and the cause when the unpack fails' {
        $Run = Invoke-SgtBootstrapCase -Scenario 'UnpackFails'

        $Run.Threw | Should -BeTrue
        $Run.ThrownType | Should -Be 'System.InvalidOperationException'
        $Run.ThrownMessage | Should -BeLike '*Microsoft.PowerShell.PSResourceGet*'
        $Run.ThrownMessage | Should -BeLike '*unpack*'
        $Run.ThrownMessage | Should -BeLike '*Sandbox: Rename-Item was reached and replaced.*'
        $Run.InnerType | Should -Not -BeNullOrEmpty
        ($Run.Call -join ',') | Should -Be 'Invoke-WebRequest,Rename-Item'
        @($Run.Call | Where-Object { $_ -in $script:SgtBootstrapLegacyCommand }) | Should -BeNullOrEmpty
    }

    It 'reaches no network' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
