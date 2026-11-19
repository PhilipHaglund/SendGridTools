BeforeDiscovery {
    $SourcePath = Join-Path -Path $PSScriptRoot -ChildPath '../../../source/Public'
    $script:AllFiles = foreach ($Name in 'New-SGAuthenticatedDomain', 'New-SGBrandedDomainLink', 'New-SGApiKey', 'Set-SGApiKey') {
        @{ Name = $Name; Path = (Join-Path -Path $SourcePath -ChildPath "$Name.ps1") }
    }
    $script:CompleterFiles = foreach ($Name in 'New-SGAuthenticatedDomain', 'New-SGApiKey', 'Set-SGApiKey') {
        @{ Name = $Name; Path = (Join-Path -Path $SourcePath -ChildPath "$Name.ps1") }
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    $script:Rules = 'PSReviewUnusedParameter', 'PSAvoidShouldContinueWithoutForce'
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'Analyzer suppressions are narrow' {
    It 'Reports no unused-parameter or ShouldContinue finding in <Name>' -ForEach $script:AllFiles {
        $Found = Invoke-ScriptAnalyzer -Path $Path -IncludeRule $script:Rules
        @($Found).Count | Should -Be 0
    }

    It 'Has no suppression of those two rules in <Name>' -ForEach $script:AllFiles {
        (Get-Content -LiteralPath $Path -Raw) | Should -Not -Match '(?is)SuppressMessage(Attribute)?\s*\(\s*[''"](PSReviewUnusedParameter|PSAvoidShouldContinueWithoutForce)[''"]'
    }

    # The analysed text is changed in memory only; the source file on disk is never written.
    It 'Reports an unused parameter added to the completer of <Name>' -ForEach $script:CompleterFiles {
        $Text = Get-Content -LiteralPath $Path -Raw
        $Text | Should -Match '\$WordToComplete = \$args\[2\]'
        $Mutated = $Text -replace '(?m)^(\s*)\$WordToComplete = \$args\[2\]', "`$1param(`$SgtUnusedProbe)`r`n`$0"
        $Found = Invoke-ScriptAnalyzer -ScriptDefinition $Mutated -IncludeRule PSReviewUnusedParameter
        @($Found | Where-Object { $_.Message -match 'SgtUnusedProbe' }).Count | Should -BeGreaterThan 0
    }

    # PSReviewUnusedParameter skips any script block that reads $PSBoundParameters, and all four functions do.
    # To prove the function-level suppression is gone, the rename to $SgtBoundProbe is done in the analysed text only.
    It 'Reports an unused parameter added to the function <Name>' -ForEach $script:AllFiles {
        $Text = Get-Content -LiteralPath $Path -Raw
        $Mutated = $Text -replace '\$PSBoundParameters', '$SgtBoundProbe'
        $Mutated = $Mutated -replace '(?m)^    param \(\r?\n', "    param (`r`n        [Parameter()][string]`$SgtUnusedProbe,`r`n"
        $Mutated | Should -Not -BeExactly $Text
        $Found = Invoke-ScriptAnalyzer -ScriptDefinition $Mutated -IncludeRule PSReviewUnusedParameter
        @($Found | Where-Object { $_.Message -match 'SgtUnusedProbe' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
