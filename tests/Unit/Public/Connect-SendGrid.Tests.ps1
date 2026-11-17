BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Connect-SendGrid parameters' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Defaults to the Region parameter set' {
        (Get-Command Connect-SendGrid).DefaultParameterSet | Should -Be 'Region'
    }

    It 'Limits -Region to Global and EU' {
        $Set = (Get-Command Connect-SendGrid).Parameters['Region'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($Set.ValidValues) | Should -Be @('Global', 'EU')
    }

    It 'Keeps -Credential at Position 0 and -Force at Position 1' {
        $P = (Get-Command Connect-SendGrid).Parameters
        ($P['Credential'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).Position | Should -Be 0
        ($P['Force'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).Position | Should -Be 1
    }

    It 'Refuses -Region together with -BaseUri without a call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            { Connect-SendGrid -Credential $Cred -Region EU -BaseUri https://example.com } | Should -Throw
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Refuses a non-https -BaseUri without a call and leaves no session' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = $null
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            { Connect-SendGrid -Credential $Cred -BaseUri http://example.com } | Should -Throw 'Unable to connect to SendGrid. Error detail: The base URI*'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
            $script:Session | Should -BeNullOrEmpty
        }
    }

    It 'Leaves an existing session untouched when -BaseUri is refused' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            { Connect-SendGrid -Credential $Cred -BaseUri http://example.com } | Should -Throw 'Unable to connect to SendGrid*'
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
