BeforeDiscovery {
    $script:Cultures = @('en-US', 'sv-SE', 'en-GB', 'tr-TR', 'th-TH')
    $script:CultureFilterCases = @(
        foreach ($Culture in $script:Cultures) {
            @{
                Culture  = $Culture
                Name     = 'two times with a zone and milliseconds'
                Filter   = 'LastEventTime -between "2024-06-30T00:00:00Z","2024-07-02T23:59:59.999Z"'
                Expected = '(last_event_time+BETWEEN+TIMESTAMP+%222024-06-30T00%3A00%3A00.000Z%22+AND+TIMESTAMP+%222024-07-02T23%3A59%3A59.000Z%22)'
            }
            @{
                Culture  = $Culture
                Name     = 'two dates whose day and month can change places'
                Filter   = 'Date -between "2024-03-04","2024-05-06"'
                Expected = '(last_event_time+BETWEEN+TIMESTAMP+%222024-03-04T00%3A00%3A00.000Z%22+AND+TIMESTAMP+%222024-05-06T00%3A00%3A00.000Z%22)'
            }
            @{
                Culture  = $Culture
                Name     = 'two times with an offset'
                Filter   = 'Timestamp -between "2024-06-30T02:00:00+02:00","2024-07-01T00:00:00+00:00"'
                Expected = '(last_event_time+BETWEEN+TIMESTAMP+%222024-06-30T00%3A00%3A00.000Z%22+AND+TIMESTAMP+%222024-07-01T00%3A00%3A00.000Z%22)'
            }
        }
    )
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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'ConvertTo-FilterQuery verbose output (D18)' {
    It 'Writes property, operator and logical operator but no value' {
        InModuleScope SendGridTools {
            $Filter = 'ToEmail -eq "one@example.com" -and Subject -like "sgt-test-subject"'
            $Streams = @(ConvertTo-FilterQuery -Filter $Filter -Verbose 4>&1)
            $Verbose = (@($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })) -join "`n"
            $Query = @($Streams | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })

            $Query.Count | Should -Be 1
            $Query[0] | Should -BeExactly '(to_email%3D%22one%40example.com%22)+AND+(subject+LIKE+%25%22sgt-test-subject%22%25)'
            $Verbose | Should -Match 'Property: to_email, Operator: -eq'
            $Verbose | Should -Match 'Property: subject, Operator: -like'
            $Verbose | Should -Match 'Logical Operator: -and'
            $Verbose | Should -Not -Match 'one@example\.com'
            $Verbose | Should -Not -Match 'one%40example'
            $Verbose | Should -Not -Match 'sgt-test-subject'
            $Verbose | Should -Not -Match 'Value'
        }
    }

    It 'Writes no date value for a date filter' {
        InModuleScope SendGridTools {
            $Filter = 'LastEventTime -between "2024-06-30T00:00:00Z","2024-07-02T00:00:00Z"'
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
                $Streams = @(ConvertTo-FilterQuery -Filter $Filter -Verbose 4>&1)
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
            $Verbose = (@($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })) -join "`n"
            $Query = @($Streams | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })

            $Query.Count | Should -Be 1
            $Query[0] | Should -Match '^\(last_event_time\+BETWEEN\+TIMESTAMP\+%22.+%22\+AND\+TIMESTAMP\+%22.+%22\)$'
            $Query[0] | Should -Match '2024-06-30'
            $Verbose | Should -Match 'DateTime: last_event_time'
            $Verbose | Should -Match 'Property: last_event_time, Operator: -between'
            $Verbose | Should -Not -Match '2024'
        }
    }
}

Describe 'ConvertTo-FilterQuery gives the same dates under every culture (D34)' {
    It 'Gives the en-US query under <Culture> for <Name>' -ForEach $script:CultureFilterCases {
        $Query = InModuleScope SendGridTools -Parameters @{ Culture = $Culture; Filter = $Filter } {
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                ConvertTo-FilterQuery -Filter $Filter
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
        }

        $Query | Should -BeExactly $Expected
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
