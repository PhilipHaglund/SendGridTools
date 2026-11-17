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
    # The authenticated domain command has a DynamicParam block that calls Get-SGIPAddress; answer it in module scope.
    Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { [pscustomobject]@{ Ip = '192.0.2.10' } }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'New-SGCombinedDomain request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the subdomain it is given to both the authenticated domain and the branded link' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -SendGridSubDomain 'email' -Confirm:$false

            $Calls = @(Get-SgtNetworkCall | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 2
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains'
            $SentDomain = $Calls[0].Body | ConvertFrom-Json
            $SentDomain.subdomain | Should -Be 'email'
            $Calls[1].Method | Should -Be 'Post'
            "$($Calls[1].Uri)" | Should -BeLike '*/whitelabel/links'
            $SentLink = $Calls[1].Body | ConvertFrom-Json
            $SentLink.subdomain | Should -Be 'email'
        }
    }

    It 'Sends no subdomain when none is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -Confirm:$false

            $Calls = @(Get-SgtNetworkCall | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 2
            $Calls[0].Method | Should -Be 'Post'
            $Calls[1].Method | Should -Be 'Post'
            $SentDomain = $Calls[0].Body | ConvertFrom-Json
            $SentLink = $Calls[1].Body | ConvertFrom-Json
            @($SentDomain.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
            @($SentLink.PSObject.Properties.Name | Sort-Object) | Should -Be @('domain')
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
