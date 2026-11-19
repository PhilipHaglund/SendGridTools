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
            @($Messages | Where-Object { $_ -ceq 'Starting process with method: Get and namespace: messages' }).Count | Should -Be 1
            @($Messages | Where-Object { $_ -ceq 'Successfully invoked "Get-SGEmailActivity" on "messages".' }).Count | Should -Be 1
            foreach ($Line in $Messages) {
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
            @($Messages | Where-Object { $_ -ceq 'Starting process with method: Get and namespace: messages' }).Count | Should -Be 1
            @($Messages | Where-Object { $_ -ceq 'Successfully invoked "Get-SGEmailActivity" on "messages".' }).Count | Should -Be 1
            foreach ($Line in $Messages) {
                $Line | Should -Not -BeLike '*one@example.com*'
                $Line | Should -Not -BeLike '*one%40example*'
                $Line | Should -Not -BeLike '*query=*'
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

Describe 'Get-SGEmailActivity binds -Value for a template property without a call (D32)' {
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

    It 'Sends the template id as the filter value and makes no other request' {
        InModuleScope SendGridTools {
            $Result = @(Get-SGEmailActivity -Property TemplateId -EQ -Value 'sgt-test-template-id')
            $Calls = (Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(template_id %3D %22sgt-test-template-id%22)'
            $Result.Count | Should -Be 1
        }
    }

    It 'Sends both template ids for two values' {
        InModuleScope SendGridTools {
            $null = @(Get-SGEmailActivity -Property TemplateId -EQ -Value 'sgt-test-template-1', 'sgt-test-template-2')
            $Calls = (Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(template_id IN (%22sgt-test-template-1%22,%22sgt-test-template-2%22))'
        }
    }

    It 'Binds -Value for TemplateName and sends the value' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            { $null = Get-SGEmailActivity -Property TemplateName -EQ -Value 'sgt-test-template-name' } | Should -Not -Throw
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
            $null = @(Get-SGEmailActivity -Property TemplateName -EQ -Value 'sgt-test-template-name')
            $Calls = (Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeLike 'https://api.sendgrid.com/v3/messages?limit=10&query=(*%22sgt-test-template-name%22)'
        }
    }

    It 'Gives -Value for <Property> the type, set and position it has for ToEmail' -ForEach @(
        @{ Property = 'TemplateId' }
        @{ Property = 'TemplateName' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property } {
            $Parameter = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value']
            $Parameter | Should -Not -BeNullOrEmpty
            $Parameter.ParameterType | Should -Be ([string[]])
            @($Parameter.ParameterSets.Keys) | Should -Be @('PropertySet')
            $Parameter.ParameterSets['PropertySet'].Position | Should -Be 2
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
