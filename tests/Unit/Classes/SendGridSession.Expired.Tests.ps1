BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $script:Cases = @(Get-SgtOverloadCase)
}

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

# D168: a session that has expired keeps saying so until it is disconnected on purpose or connected again.

Describe 'SendGridSession remembers that it expired (D168)' {
    BeforeEach {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
        }
    }

    It 'Says expired on the second call after the session expired <Name>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Case = $_; Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            $Expired = 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage $Expired
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage $Expired
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage $Expired
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Says expired after Connect() found the session expired <Name>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Case = $_; Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            $Expired = 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            { $Session.Connect() } | Should -Throw -ExpectedMessage $Expired
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage $Expired
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Says connect first after an expired session is disconnected <Name>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Case = $_; Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'The SendGrid session has expired.*'
            $Session.Disconnect()
            $Session._Expired | Should -BeFalse
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Works again after a successful Connect(credential) on an expired session <Name>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Case = $_; Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ answer = 'stub-answer' })
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'The SendGrid session has expired.*'
            $Session._Expired | Should -BeTrue
            $Session.Connect($Cred)
            $Session._Expired | Should -BeFalse
            (Invoke-SgtOverload -Session $Session -Case $Case).answer | Should -Be 'stub-answer'
        }
    }

    It 'Keeps the flag after a failed Connect(credential) <Name>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Case = $_; Cred = $script:Cred } {
            Set-SgtNetworkStub -Throw 'boom'
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'The SendGrid session has expired.*'
            { $Session.Connect($Cred) } | Should -Throw -ExpectedMessage 'Unable to connect to SendGrid. boom'
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
        }
    }

    It 'Does not set the flag for a session that was never connected <Name>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Case = $_; Cred = $script:Cred } {
            $Session = [SendGridSession]::new()
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            $Session._Expired | Should -BeFalse
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
