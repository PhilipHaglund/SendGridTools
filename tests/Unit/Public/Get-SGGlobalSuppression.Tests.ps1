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

Describe 'Get-SGGlobalSuppression encodes the address in the query (D62)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends only the encoded address without -Limit' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGGlobalSuppression -EmailAddress 'a+b@example.com'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            ([uri]$Calls[0].Uri).Query | Should -BeExactly '?email=a%2Bb%40example.com'
        }
    }

    It 'Sends the given limit and the encoded address with -Limit 10' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGGlobalSuppression -EmailAddress 'a+b@example.com' -Limit 10

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

            $null = Get-SGGlobalSuppression -EmailAddress $Address

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Uri = [uri]$Calls[0].Uri
            $Uri.Fragment | Should -BeExactly ''
            $Uri.Query.EndsWith($Tail) | Should -BeTrue
            @($Uri.Query.TrimStart('?') -split '&').Count | Should -Be 1
        }
    }

    It 'Sends one request per address, each with one email value' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGGlobalSuppression -EmailAddress 'one@example.com', 'two@example.com'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            ([uri]$Calls[0].Uri).Query | Should -BeExactly '?email=one%40example.com'
            ([uri]$Calls[1].Uri).Query | Should -BeExactly '?email=two%40example.com'
        }
    }

    It 'Sends the query as before without -EmailAddress' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1 })

            $null = Get-SGGlobalSuppression

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).Query | Should -BeExactly ''
        }
    }
}

Describe 'Get-SGGlobalSuppression refuses an empty -EmailAddress (D116)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response @([pscustomobject]@{ email = 'user@example.com' })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Case> at binding and makes no call' -TestCases @(
        @{ Case = '$null'; Splat = @{ EmailAddress = $null } }
        @{ Case = '@()'; Splat = @{ EmailAddress = @() } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGGlobalSuppression @Splat } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Refuses <Case> at binding and makes no call' -TestCases @(
        @{ Case = "''"; Splat = @{ EmailAddress = '' } }
        @{ Case = "@('')"; Splat = @{ EmailAddress = @('') } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGGlobalSuppression @Splat } | Should -Throw -ErrorId 'ParameterArgument*Error*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Refuses an empty value from the pipeline <Case> and makes no call' -TestCases @(
        @{ Case = 'as a string'; ByProperty = $false }
        @{ Case = 'by property EmailAddress'; ByProperty = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ ByProperty = $ByProperty } {
            # A pipeline binding error follows the caller's preference, not -ErrorAction; CI's pwsh shell sets Stop.
            $ErrorActionPreference = 'Continue'
            if ($ByProperty) {
                $Streams = @([pscustomobject]@{ EmailAddress = '' } | Get-SGGlobalSuppression 2>&1)
            }
            else {
                $Streams = @('' | Get-SGGlobalSuppression 2>&1)
            }
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            # A piped string that is not an address finds no parameter to bind by value, so its error is InputObjectNotBound.
            "$($Errs[0].FullyQualifiedErrorId)" | Should -Match '^(ParameterArgument|InputObjectNotBound)'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    # PowerShell may bind the object by value when its EmailAddress is $null; only the absence of a list request is pinned.
    It 'Sends no list request for an object whose EmailAddress is $null' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $null = @([pscustomobject]@{ EmailAddress = $null } | Get-SGGlobalSuppression 2>&1)

            $Calls = @(@(Get-SgtNetworkCall)[0])
            @($Calls | Where-Object { ([uri]$_.Uri).Query -notmatch 'email=' }).Count | Should -Be 0
        }
    }

    It 'Sends only the valid value when an empty value comes first in the pipeline' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $Streams = @([pscustomobject]@{ EmailAddress = '' }, [pscustomobject]@{ EmailAddress = 'user@example.com' } | Get-SGGlobalSuppression 2>&1)
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/suppression/unsubscribes?email=user%40example.com'
        }
    }

    It 'Sends the same request as before for a valid value' {
        InModuleScope SendGridTools {
            $null = Get-SGGlobalSuppression -EmailAddress 'user@example.com'

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/suppression/unsubscribes?email=user%40example.com'
        }
    }

    It 'Sends the same request as before without parameters' {
        InModuleScope SendGridTools {
            $null = Get-SGGlobalSuppression

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/suppression/unsubscribes'
        }
    }
}

Describe 'Get-SGGlobalSuppression help (D117)' {
    It 'Says that an empty -EmailAddress is refused' {
        $Text = ((Get-Help Get-SGGlobalSuppression -Parameter EmailAddress).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -BeLike '*An empty value is refused.'
    }

    It 'Says in the comment at -EmailAddress that an empty value is refused' {
        (Get-Command Get-SGGlobalSuppression).Definition | Should -Match '# [^\r\n]*An empty value is refused\.\r?\n\s*\[Parameter\([^)]*\)\]\s*(\[[^\r\n]*\]\s*)*\$EmailAddress\b'
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
