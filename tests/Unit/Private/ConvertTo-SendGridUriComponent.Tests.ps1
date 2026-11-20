BeforeDiscovery {
    $Script:IsCore = $PSVersionTable.PSEdition -eq 'Core'
    $Script:Cases = @(
        @{ Text = 'a/b'; Expected = 'a%2Fb' }
        @{ Text = 'a?b'; Expected = 'a%3Fb' }
        @{ Text = 'a#b'; Expected = 'a%23b' }
        @{ Text = 'a b'; Expected = 'a%20b' }
        @{ Text = 'a%b'; Expected = 'a%25b' }
        @{ Text = 'a!b'; Expected = 'a%21b' }
        @{ Text = 'a*b'; Expected = 'a%2Ab' }
        @{ Text = "a'b"; Expected = 'a%27b' }
        @{ Text = 'a(b)'; Expected = 'a%28b%29' }
        @{ Text = 'abc-1.2_3~'; Expected = 'abc-1.2_3~' }
        @{ Text = '!='; Expected = '%21%3D' }
        @{ Text = 'a+b@example.com'; Expected = 'a%2Bb%40example.com' }
        @{ Text = 'a&b=c'; Expected = 'a%26b%3Dc' }
        @{ Text = '"x"'; Expected = '%22x%22' }
        @{ Text = [string][char]0x00E9; Expected = '%C3%A9' }
        @{ Text = ''; Expected = '' }
        @{ Text = $null; Expected = '' }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'ConvertTo-SendGridUriComponent' {
    It 'Encodes <Text> as <Expected>' -ForEach $Script:Cases {
        $Result = InModuleScope SendGridTools -ArgumentList @(, $Text) -ScriptBlock {
            param($Value)
            ConvertTo-SendGridUriComponent $Value
        }
        $Result | Should -BeExactly $Expected
    }

    It 'Gives the same text as [uri]::EscapeDataString in PowerShell 7 for <Text>' -ForEach $Script:Cases -Skip:(-not $Script:IsCore) {
        $Result = InModuleScope SendGridTools -ArgumentList @(, $Text) -ScriptBlock {
            param($Value)
            ConvertTo-SendGridUriComponent $Value
        }
        $Result | Should -BeExactly ([uri]::EscapeDataString($Text))
    }

    It 'Leaves no EscapeDataString in source/ outside the function, and one inside it' {
        $SourceRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../source')).Path
        $Function = 'ConvertTo-SendGridUriComponent.ps1'
        $Hits = foreach ($File in Get-ChildItem -Path $SourceRoot -Filter '*.ps1' -Recurse) {
            $LineNumber = 0
            foreach ($Line in Get-Content -Path $File.FullName) {
                $LineNumber++
                if ($Line -match 'EscapeDataString') { '{0}:{1}' -f $File.FullName, $LineNumber }
            }
        }
        $Outside = @($Hits | Where-Object { $_ -notlike "*$Function`:*" })
        ($Outside -join '; ') | Should -BeExactly '' -Because 'only the private function may call EscapeDataString'
        # The help text of the function names [uri]::EscapeDataString in prose; only the call (with its opening parenthesis) counts.
        $Calls = @(Select-String -Path (Join-Path -Path $SourceRoot -ChildPath "Private/$Function") -Pattern 'EscapeDataString\(' -SimpleMatch:$false)
        $Calls.Count | Should -Be 1
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
