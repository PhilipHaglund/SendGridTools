BeforeDiscovery {
    $script:Cultures = @('en-US', 'sv-SE', 'en-GB', 'tr-TR', 'th-TH')
    $script:Pairs = @(
        @{ Text = 'id'; Expected = 'Id' }
        @{ Text = 'ip'; Expected = 'Ip' }
        @{ Text = 'is_enabled'; Expected = 'Is_Enabled' }
        @{ Text = 'ID'; Expected = 'Id' }
        @{ Text = 'TITLE'; Expected = 'Title' }
        @{ Text = 'last_validation_attempt_at'; Expected = 'Last_Validation_Attempt_At' }
    )
    $script:TitleCases = @(
        foreach ($Culture in $script:Cultures) {
            foreach ($Pair in $script:Pairs) {
                @{ Culture = $Culture; Text = $Pair.Text; Expected = $Pair.Expected }
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

Describe 'ConvertTo-TitleCase uses the invariant culture (D34)' {
    AfterEach {
        Remove-Variable -Name SgtTestCultureName -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Gives <Expected> for <Text> under <Culture>' -ForEach $script:TitleCases {
        $global:SgtTestCultureName = $Culture
        # The module no longer calls Get-Culture. The mock stays: in Windows PowerShell 5.1 Get-Culture does not follow the thread culture, so only this mock turns the test red if (Get-Culture).TextInfo comes back.
        Mock -CommandName Get-Culture -ModuleName SendGridTools -MockWith { [System.Globalization.CultureInfo]::GetCultureInfo($global:SgtTestCultureName) }
        $Result = InModuleScope SendGridTools -Parameters @{ Culture = $Culture; Text = $Text } {
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                ConvertTo-TitleCase -InputObject $Text
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
        }

        $Result | Should -BeExactly $Expected
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
