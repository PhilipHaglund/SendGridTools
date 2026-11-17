BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $Targets = @(
        @{ Target = 'Connect(credential)'; Label = 'Connect(credential)'; Case = @{} }
        @{ Target = 'Connect()'; Label = 'Connect()'; Case = @{} }
    )
    foreach ($OverloadCase in Get-SgtOverloadCase) {
        $Targets += @{ Target = 'InvokeQuery'; Label = ('InvokeQuery {0}' -f $OverloadCase.Name); Case = $OverloadCase }
        $Targets += @{ Target = 'Invoke-SendGrid'; Label = ('Invoke-SendGrid with {0}' -f $OverloadCase.Name); Case = $OverloadCase }
    }
    $script:Scenarios = foreach ($Entry in $Targets) {
        foreach ($Scenario in 'success', 'failure with error details', 'failure without error details') {
            @{ Target = $Entry.Target; Label = $Entry.Label; Case = $Entry.Case; Scenario = $Scenario }
        }
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'API key exposure' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Does not leak the key from <Label> (<Scenario>)' -ForEach $script:Scenarios {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Target = $Target; Case = $Case; Scenario = $Scenario } {
            switch ($Scenario) {
                'success' { Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'mock-response' }) }
                'failure with error details' { Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}') }
                default { Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure') }
            }

            $Leak = Get-SgtLeakText -Action { Invoke-SgtTarget -Target $Target -Case $Case -Credential $Cred }

            $Leak.Threw | Should -Be ($Scenario -ne 'success')
            $Leak.Text | Should -Not -BeLike '*test-key-not-real*'
        }
    }

    It 'Captures the verbose stream (positive control)' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'mock-response' })
            $Case = @{ Method = 'Post'; Endpoint = 'mail/send'; HasBody = $true; HasObo = $false; Body = @{ Key = 'value' }; Obo = $null }

            $Leak = Get-SgtLeakText -Action { Invoke-SgtTarget -Target 'InvokeQuery' -Case $Case -Credential $Cred }

            $Leak.Verbose | Should -BeLike '*ContentBody: Key:*'
            $Leak.Text | Should -BeLike '*ContentBody: Key:*'
            $Leak.Text | Should -Not -BeLike '*test-key-not-real*'
        }
    }
}

Describe 'Leak detector self-test' {
    # Proves Get-SgtLeakText sees the placeholder on every channel, so a green security test is not vacuous.
    # The planting code runs in module scope, the same path the real cases use.
    It 'Detects the placeholder planted through <Channel>' -ForEach @(
        @{ Channel = 'Write-Verbose' }
        @{ Channel = 'Write-Debug' }
        @{ Channel = 'output' }
        @{ Channel = 'throw' }
        @{ Channel = 'ErrorDetails message' }
        @{ Channel = 'ErrorDetails message passed through SendGrid error formatting' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Channel = $Channel } {
            $Leak = Get-SgtLeakText -Action {
                switch ($Channel) {
                    'Write-Verbose' { Write-Verbose -Message 'planted test-key-not-real' }
                    'Write-Debug' { Write-Debug -Message 'planted test-key-not-real' }
                    'output' { 'planted test-key-not-real' }
                    'throw' { throw 'planted test-key-not-real' }
                    'ErrorDetails message' { throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"planted test-key-not-real"}]}') }
                    default { throw ('SendGrid Error: "{0}"' -f 'planted test-key-not-real') }
                }
            }
            $Leak.Text | Should -BeLike '*test-key-not-real*'
        }
    }

    It 'Reports no hit for an action that plants nothing' {
        InModuleScope SendGridTools {
            $Leak = Get-SgtLeakText -Action { Write-Verbose -Message 'nothing here'; 'plain output' }
            $Leak.Text | Should -Not -BeLike '*test-key-not-real*'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
