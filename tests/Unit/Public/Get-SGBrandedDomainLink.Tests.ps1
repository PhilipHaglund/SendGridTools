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

Describe 'Get-SGBrandedDomainLink encodes the id in the path (D153)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; subdomain = 'sgt-test-sub'; domain = 'example.com'; valid = $false })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Puts <Name> in one path segment' -ForEach @(
        @{ Name = 'an id with a slash, a question mark and a hash'; Id = 'a/b?c#d'; Segment = 'a%2Fb%3Fc%23d' }
        @{ Name = 'a numeric id'; Id = '1001'; Segment = '1001' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Id = $Id; Segment = $Segment } {
            $null = Get-SGBrandedDomainLink -UniqueId $Id -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -BeGreaterThan 0
            foreach ($Call in $Calls) {
                $Call.Uri.OriginalString | Should -BeLike "https://api.sendgrid.com/v3/whitelabel/links/$Segment*"
                $Call.Uri.OriginalString | Should -Not -BeLike '*/a/b*'
                $Call.Uri.OriginalString | Should -Not -Match '[?#]'
            }
            $Calls[-1].Method | Should -Be 'Get'
            $Calls[-1].Uri.OriginalString | Should -BeExactly "https://api.sendgrid.com/v3/whitelabel/links/$Segment"
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
