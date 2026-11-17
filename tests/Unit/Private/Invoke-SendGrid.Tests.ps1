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

Describe 'Invoke-SendGrid without a session' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Throws the connect-first error when no session exists' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Response $null
            $script:Session = $null
            { Invoke-SendGrid -Method Get -Namespace 'scopes' } | Should -Throw -ExpectedMessage 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-SendGrid with a connected session' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Makes one request for <Name> with matching body and on-behalf-of' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = @{ Method = $Method; Endpoint = $Endpoint; HasBody = $HasBody; HasObo = $HasObo; Body = $Body; Obo = $Obo } } {
            $Response = [pscustomobject]@{ name = 'mock-response' }
            Set-SgtNetworkStub -Response $Response
            $script:Session = [SendGridSession]::new()
            $script:Session.Connect($Cred)
            # The connect GET is not part of the request under test.
            Set-SgtNetworkStub -Response $Response

            $Params = @{ Method = $Case.Method; Namespace = $Case.Endpoint }
            if ($Case.HasBody) { $Params['ContentBody'] = $Case.Body }
            if ($Case.HasObo) { $Params['OnBehalfOf'] = $Case.Obo }
            $Result = Invoke-SendGrid @Params

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Call = $Calls[0]
            $Call.Method | Should -Be $Case.Method
            $Call.Uri.AbsoluteUri | Should -Be ('https://api.sendgrid.com/v3/{0}' -f $Case.Endpoint)
            $Call.BodyPassed | Should -Be $Case.HasBody
            $Call.Headers.ContainsKey('on-behalf-of') | Should -Be $Case.HasObo
            if ($Case.HasObo) {
                $Call.Headers['on-behalf-of'] | Should -Be $Case.Obo
            }
            @($Result).Count | Should -Be 1
            @($Result)[0].Name | Should -Be 'mock-response'
        }
    }

    It 'Flattens a results wrapper into the contained objects' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Response = [pscustomobject]@{
                results = @(
                    [pscustomobject]@{ id = 1; name = 'first' }
                    [pscustomobject]@{ id = 2; name = 'second' }
                )
            }
            Set-SgtNetworkStub -Response $Response
            $script:Session = [SendGridSession]::new()
            $script:Session.Connect($Cred)

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 2
            $Result[0].Id | Should -Be 1
            $Result[0].Name | Should -Be 'first'
            $Result[1].Id | Should -Be 2
            $Result[1].Name | Should -Be 'second'
        }
    }

    It 'Converts an int64 lastat property to a DateTime named Lastat' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Response = [pscustomobject]@{
                results = @([pscustomobject]@{ email = 'user@example.com'; lastat = [int64]1700000000 })
            }
            Set-SgtNetworkStub -Response $Response
            $script:Session = [SendGridSession]::new()
            $script:Session.Connect($Cred)

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 1
            $Result[0].Lastat | Should -BeOfType [datetime]
            $Result[0].Lastat | Should -Be ([datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds(1700000000))
            $Result[0].Lastat.ToString('yyyy-MM-ddTHH:mm:ss', [cultureinfo]::InvariantCulture) | Should -Be '2023-11-14T22:13:20'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
