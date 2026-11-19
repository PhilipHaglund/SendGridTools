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

Describe 'Get-SGEmailActivity verbose output and query (D18)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the same query and writes no value for -Property' {
        InModuleScope SendGridTools {
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Streams = @(& { Get-SGEmailActivity -Property ToEmail -EQ -Value 'one@example.com' -Verbose } 4>&1)
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            $Messages = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(to_email %3D %22one%40example.com%22)'
            @($Messages | Where-Object { $_ -ceq 'Filter Query: Property: ToEmail, Operator: =' }).Count | Should -Be 1
            # Two notes of Invoke-SendGrid ("Starting process with method", "Successfully invoked") name the namespace with the query; it is outside D18's listed texts and is reported as a finding.
            foreach ($Line in @($Messages | Where-Object { $_ -notlike 'Starting process with method:*' -and $_ -notlike 'Successfully invoked*' })) {
                $Line | Should -Not -BeLike '*one@example.com*'
                $Line | Should -Not -BeLike '*one%40example*'
                $Line | Should -Not -BeLike '*query=*'
            }
        }
    }

    It 'Sends the same query and writes no value for -Filter' {
        InModuleScope SendGridTools {
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Streams = @(& { Get-SGEmailActivity -Filter 'ToEmail -eq "one@example.com"' -Verbose } 4>&1)
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            $Messages = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(to_email%3D%22one%40example.com%22)'
            ($Messages -join "`n") | Should -Match 'Property: to_email, Operator: -eq'
            # Two notes of Invoke-SendGrid ("Starting process with method", "Successfully invoked") name the namespace with the query; it is outside D18's listed texts and is reported as a finding.
            foreach ($Line in @($Messages | Where-Object { $_ -notlike 'Starting process with method:*' -and $_ -notlike 'Successfully invoked*' })) {
                $Line | Should -Not -BeLike '*one@example.com*'
                $Line | Should -Not -BeLike '*one%40example*'
            }
        }
    }

    It 'Returns the messages' {
        InModuleScope SendGridTools {
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Result = @(Get-SGEmailActivity -Property ToEmail -EQ -Value 'one@example.com')
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            $Result.Count | Should -Be 1
            $Result[0].MsgId | Should -Be 'sgt-test-message-id'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
