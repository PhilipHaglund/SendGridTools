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

Describe 'Get-SGBlock encodes the address in the query (D62)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends limit=100 and the encoded address without -Limit' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGBlock -EmailAddress 'a+b@example.com'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            ([uri]$Calls[0].Uri).Query | Should -BeExactly '?limit=100&email=a%2Bb%40example.com'
        }
    }

    It 'Sends the given limit and the encoded address with -Limit 10' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGBlock -EmailAddress 'a+b@example.com' -Limit 10

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).Query | Should -BeExactly '?limit=10&email=a%2Bb%40example.com'
        }
    }

    It 'Keeps <Address> inside the email value' -ForEach @(
        @{ Address = 'one#tag@example.com'; Tail = 'email=one%23tag%40example.com' }
        @{ Address = 'a&b@example.com'; Tail = 'email=a%26b%40example.com' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Address = $Address; Tail = $Tail } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGBlock -EmailAddress $Address

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Uri = [uri]$Calls[0].Uri
            $Uri.Fragment | Should -BeExactly ''
            $Uri.Query.EndsWith($Tail) | Should -BeTrue
            @($Uri.Query.TrimStart('?') -split '&').Count | Should -Be 2
        }
    }

    It 'Sends one request per address, each with one email value' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGBlock -EmailAddress 'one@example.com', 'two@example.com'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            ([uri]$Calls[0].Uri).Query | Should -BeExactly '?limit=100&email=one%40example.com'
            ([uri]$Calls[1].Uri).Query | Should -BeExactly '?limit=100&email=two%40example.com'
        }
    }

    It 'Sends the query as before without -EmailAddress' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGBlock

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).Query | Should -BeExactly '?limit=100'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
