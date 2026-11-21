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

Describe 'Get-SGBounceByClassification request' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ classification = 'Content'; total_bounces = 12 })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Get to suppression/bounces/classifications with no query and no body' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications'
            $Calls[0].BodyPassed | Should -BeFalse
            $Calls[0].Headers.ContainsKey('on-behalf-of') | Should -BeFalse
        }
    }

    It 'Adds the classification to the path' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification -Classification Content

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications/Content'
        }
    }

    It 'Takes the classification as the first positional argument' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification 'Reputation'

            $Calls = Get-SgtNetworkCall
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications/Reputation'
        }
    }

    It 'Sends -StartDate and -EndDate as start_date and end_date in that order' {
        InModuleScope SendGridTools {
            # Date strings carry no time zone and the conversion back to text is pure arithmetic, so the result does not depend on the machine's time zone.
            $null = Get-SGBounceByClassification -EndDate '2026-02-15' -StartDate '2026-01-01'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications?start_date=2026-01-01&end_date=2026-02-15'
        }
    }

    It 'Sends a start date alone without an end_date' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification -StartDate '2026-01-01'

            $Calls = Get-SgtNetworkCall
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications?start_date=2026-01-01'
        }
    }

    It 'Sends an end date alone without a start_date' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification -EndDate '2026-02-15'

            $Calls = Get-SgtNetworkCall
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications?end_date=2026-02-15'
        }
    }

    It 'Accepts a unix timestamp as the date' {
        InModuleScope SendGridTools {
            # 1767225600 is 2026-01-01T00:00:00Z.
            $null = Get-SGBounceByClassification -StartDate 1767225600

            $Calls = Get-SgtNetworkCall
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications?start_date=2026-01-01'
        }
    }

    It 'Combines the classification with both dates' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification -Classification 'Invalid Address' -StartDate '2026-01-01' -EndDate '2026-02-15'

            $Calls = Get-SgtNetworkCall
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/suppression/bounces/classifications/Invalid%20Address?start_date=2026-01-01&end_date=2026-02-15'
        }
    }

    It 'Refuses an unknown classification at binding and makes no call' {
        InModuleScope SendGridTools {
            $Caught = $null
            try { $null = Get-SGBounceByClassification -Classification 'NotAClassification' } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools {
            $null = Get-SGBounceByClassification -OnBehalfOf 'subuser-placeholder'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Returns the answer with title-case property names' {
        InModuleScope SendGridTools {
            $Result = Get-SGBounceByClassification

            $Result.Classification | Should -BeExactly 'Content'
            $Result.TotalBounces | Should -Be 12
        }
    }

    It 'Wraps a SendGrid error with the cause' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Caught = $null
            try { $null = Get-SGBounceByClassification } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeLike 'Failed to retrieve SendGrid bounce classifications. SendGrid Error*bad request*'
            $Caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
