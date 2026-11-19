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

Describe 'Remove-SGApiKey ids from the pipeline' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the request to the right path for <Name> from the pipeline' -ForEach @(
        @{ Name = 'a long'; Ids = @([long]1001); TypeName = 'System.Int64' }
        @{ Name = 'an integer'; Ids = @([int]1001); TypeName = 'System.Int32' }
        @{ Name = 'a string'; Ids = @('1001'); TypeName = 'System.String' }
        @{ Name = 'an object with an Id property'; Ids = @([pscustomobject]@{ Id = 1001 }); TypeName = 'System.Management.Automation.PSCustomObject' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Ids = $Ids; TypeName = $TypeName } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            # Guard: the value that is piped really has the intended type (an int must not stand in for a long).
            @($Ids).Count | Should -Be 1
            @($Ids)[0].GetType().FullName | Should -Be $TypeName

            $null = $Ids | Remove-SGApiKey -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys/1001'
        }
    }

    It 'Fails with a conversion error and sends nothing for a double from the pipeline' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $Ids = @([double]1001.5)
            @($Ids)[0].GetType().FullName | Should -Be 'System.Double'

            { $Ids | Remove-SGApiKey -Confirm:$false } | Should -Throw '*Failed to convert InputObject to Id.*'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }
}
Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
