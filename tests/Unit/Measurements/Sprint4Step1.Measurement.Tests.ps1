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
    $script:Fixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/whitelabel-domains-page.json'
    # Get-SGIPAddress is answered in module scope, so no binding of New-SGAuthenticatedDomain reaches the transport for it.
    Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { [pscustomobject]@{ Ip = '192.0.2.10' }, [pscustomobject]@{ Ip = '192.0.2.11' } }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 4 step 1 measurements (D8, D10). Each It writes one MEASURE line with type names, parameter names and
# True/False only, and asserts nothing about the measured value, so the same file measures any version of the module.
Describe 'Sprint 4 step 1 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'D8: a third positional argument (<Name>) binds to a parameter' -ForEach @(
        @{ Name = 'a name'; Value = 'subuser-placeholder' }
        @{ Name = 'an offered IP address'; Value = '192.0.2.10' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Value = $Value } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $Outcome = try {
                $null = New-SGAuthenticatedDomain 'example.com' 'email' $Value -Confirm:$false -ErrorAction Stop
                $Calls = Get-SgtNetworkCall
                $Sent = $Calls[0].Body | ConvertFrom-Json
                $Bound = @(foreach ($Key in 'username', 'ips') { if ($Sent.PSObject.Properties.Name -contains $Key) { $Key } })
                'bound to body field: {0}' -f ($Bound -join ',')
            }
            catch {
                'threw {0}, ErrorId {1}' -f $_.Exception.GetType().Name, $_.FullyQualifiedErrorId
            }
            $Outcome
        }
        Write-Host ('MEASURE D8 [{0} {1}] third positional {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D10: the Id type after Get-SGAuthenticatedDomain (<Name>)' -ForEach @(
        @{ Name = 'list' }
        @{ Name = 'single id' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture; Name = $Name } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            # The fixture is parsed by ConvertFrom-Json in the running shell, the parser Invoke-RestMethod uses for JSON in that edition.
            $Items = @(Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json | ForEach-Object { $_ })
            if ($Name -eq 'list') {
                Set-SgtPagedNetworkStub -Items $Items -Shape List
                $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)
            }
            else {
                Set-SgtNetworkStub -Response $Items[0]
                $Out = @(Get-SGAuthenticatedDomain -UniqueId '1001' -Confirm:$false)
            }
            $IdType = $Out[0].Id.GetType().FullName
            # Pipe that Id alone to a command that collects ids from InputObject, under WhatIf so nothing would be sent.
            Set-SgtNetworkStub -Response $Items[0]
            $Accepted = try { $null = $Out[0].Id | Set-SGAuthenticatedDomain -SetDefault -WhatIf -ErrorAction Stop; $true } catch { $false }
            'Id type {0}; source id type {1}; piped Id accepted by Set-SGAuthenticatedDomain: {2}' -f $IdType, $Items[0].id.GetType().FullName, $Accepted
        }
        Write-Host ('MEASURE D10 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
