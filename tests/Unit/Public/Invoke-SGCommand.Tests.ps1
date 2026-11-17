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

Describe 'Invoke-SGCommand request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the relative path <Path> to the <Name> host' -ForEach @(
        foreach ($P in 'scopes', '/scopes', 'v3/scopes', '/v3/scopes') {
            @{ Name = 'global'; Base = 'https://api.sendgrid.com/v3'; Path = $P }
            @{ Name = 'EU'; Base = 'https://api.eu.sendgrid.com/v3'; Path = $P }
        }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Base = $Base; Path = $Path } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session._BaseURL = [uri]$Base
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            $null = Invoke-SGCommand -Namespace $Path -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be "$Base/scopes"
        }
    }

    It 'Sends the full URL <Url> to <Expected>' -ForEach @(
        @{ Base = 'https://api.sendgrid.com/v3'; Url = 'https://api.sendgrid.com/v3/scopes'; Expected = 'https://api.sendgrid.com/v3/scopes' }
        @{ Base = 'https://api.sendgrid.com/v3'; Url = 'https://api.sendgrid.com/scopes'; Expected = 'https://api.sendgrid.com/v3/scopes' }
        @{ Base = 'https://api.eu.sendgrid.com/v3'; Url = 'https://api.eu.sendgrid.com/v3/scopes'; Expected = 'https://api.eu.sendgrid.com/v3/scopes' }
        @{ Base = 'https://api.eu.sendgrid.com/v3'; Url = 'https://API.EU.SendGrid.com/v3/scopes'; Expected = 'https://api.eu.sendgrid.com/v3/scopes' }
        @{ Base = 'https://api.eu.sendgrid.com/v3'; Url = 'https://api.eu.sendgrid.com/v3/whitelabel/domains'; Expected = 'https://api.eu.sendgrid.com/v3/whitelabel/domains' }
        @{ Base = 'https://proxy.example.com/sendgrid/v3'; Url = 'https://proxy.example.com/sendgrid/v3/scopes'; Expected = 'https://proxy.example.com/sendgrid/v3/scopes' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Base = $Base; Url = $Url; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session._BaseURL = [uri]$Base
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            $null = Invoke-SGCommand -Namespace $Url -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be $Expected
        }
    }

    It 'Keeps the query parameters on a full EU URL' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session._BaseURL = [uri]'https://api.eu.sendgrid.com/v3'
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            $null = Invoke-SGCommand -Namespace 'https://api.eu.sendgrid.com/v3/subusers' -QueryParameters 'limit=5' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/subusers?limit=5'
        }
    }

    It 'Does not remove a v3/ inside a relative path' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            $null = Invoke-SGCommand -Namespace '/v3/templates/v3x/v3/abc' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/templates/v3x/v3/abc'
        }
    }

    It 'Refuses <Url> on a <Name> session and makes no request' -ForEach @(
        @{ Name = 'global'; Base = 'https://api.sendgrid.com/v3'; Url = 'https://api.eu.sendgrid.com/v3/scopes' }
        @{ Name = 'EU'; Base = 'https://api.eu.sendgrid.com/v3'; Url = 'https://api.sendgrid.com/v3/scopes' }
        @{ Name = 'global'; Base = 'https://api.sendgrid.com/v3'; Url = 'https://example.net/v3/scopes' }
        @{ Name = 'global'; Base = 'https://api.sendgrid.com/v3'; Url = 'https://api.sendgrid.com.example.net/v3/scopes' }
        @{ Name = 'global'; Base = 'https://api.sendgrid.com/v3'; Url = 'http://api.sendgrid.com/v3/scopes' }
        @{ Name = 'global'; Base = 'https://api.sendgrid.com/v3'; Url = 'https://api.sendgrid.com:8443/v3/scopes' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Base = $Base; Url = $Url } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session._BaseURL = [uri]$Base
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            { Invoke-SGCommand -Namespace $Url -Confirm:$false } | Should -Throw 'Refusing to send the request to*'

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Sends <Url> only to the session host' -ForEach @(
        @{ Url = 'https://api.sendgrid.com//evil.example.net/x' }
        @{ Url = 'https://api.sendgrid.com/v3/@evil.example.net/x' }
        @{ Url = '//evil.example.net/x' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Url = $Url } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session._BaseURL = [uri]'https://api.sendgrid.com/v3'
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            $null = Invoke-SGCommand -Namespace $Url -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).Host | Should -Be 'api.sendgrid.com'
        }
    }

    It 'Refuses a foreign full URL under -WhatIf and makes no request' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session._BaseURL = [uri]'https://api.sendgrid.com/v3'
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            { Invoke-SGCommand -Namespace 'https://example.net/v3/scopes' -WhatIf } | Should -Throw 'Refusing to send the request to*'

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Refuses a full URL when there is no session' {
        InModuleScope SendGridTools {
            $script:Session = $null
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 1 })

            { Invoke-SGCommand -Namespace 'https://api.sendgrid.com/v3/scopes' -Confirm:$false } | Should -Throw 'You must call the Connect-SendGrid cmdlet*'

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
