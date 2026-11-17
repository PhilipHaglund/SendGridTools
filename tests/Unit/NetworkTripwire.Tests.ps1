BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'Network tripwire helper' {
    BeforeEach {
        Enable-SgtNetworkTripwire
        Assert-SgtNetworkTripwireActive
    }
    AfterEach {
        Disable-SgtNetworkTripwire
    }

    It 'Throws and records Invoke-RestMethod when a session class calls it unmocked' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            # Loopback target: a broken tripwire still cannot reach the internet.
            $Session = [SendGridSession]::new()
            $Session._BaseURL = [uri]'http://127.0.0.1:9/v3'
            { $Session.Connect($Cred) } | Should -Throw '*Unmocked network call*'
        }
        Get-SgtUnmockedNetworkCall | Should -Contain 'Invoke-RestMethod'
    }

    It 'Records a direct Invoke-WebRequest the same way' {
        { Invoke-WebRequest -Uri 'http://127.0.0.1:9/' } | Should -Throw '*Unmocked network call*'
        Get-SgtUnmockedNetworkCall | Should -Contain 'Invoke-WebRequest'
    }

    It 'Lets a mock win and records nothing' {
        Mock -CommandName Invoke-RestMethod -ModuleName SendGridTools -MockWith { 'mocked' }
        InModuleScope SendGridTools {
            Invoke-RestMethod -Uri 'http://127.0.0.1:9/'
        } | Should -Be 'mocked'
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'Lets a stub answer a class call, logs it and records nothing as unmocked' {
        $global:SgtNetworkStub = { 'stubbed' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Session = [SendGridSession]::new()
            $Session._BaseURL = [uri]'http://127.0.0.1:9/v3'
            { $Session.Connect($Cred) } | Should -Not -Throw
        }
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        @($global:SgtNetworkCall).Count | Should -Be 1
        $global:SgtNetworkCall[0].Uri.AbsoluteUri | Should -Be 'http://127.0.0.1:9/v3/scopes'
    }

    It 'Reports the tripwire as active while enabled' {
        { Assert-SgtNetworkTripwireActive } | Should -Not -Throw
    }

    It 'Fails the active check and the unmocked-call read when the tripwire is disabled' {
        Disable-SgtNetworkTripwire
        try {
            { Assert-SgtNetworkTripwireActive } | Should -Throw '*not active*'
            { Get-SgtUnmockedNetworkCall } | Should -Throw '*state is missing*'
        } finally {
            Enable-SgtNetworkTripwire
        }
        { Assert-SgtNetworkTripwireActive } | Should -Not -Throw
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'Removes the functions and the variable when disabled' {
        Disable-SgtNetworkTripwire
        Test-Path -Path 'Function:\Invoke-RestMethod' | Should -BeFalse
        Test-Path -Path 'Function:\Invoke-WebRequest' | Should -BeFalse
        Test-Path -Path 'Variable:\global:SgtUnmockedNetworkCall' | Should -BeFalse
    }
}

Describe 'Static rule for every unit test file' {
    BeforeDiscovery {
        $UnitRoot = $PSScriptRoot
        $script:Files = @(
            Get-ChildItem -Path $UnitRoot -Filter '*.Tests.ps1' -Recurse -File |
                Where-Object { $_.Name -ne 'NetworkTripwire.Tests.ps1' } |
                ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($UnitRoot.Length).TrimStart('\', '/') } }
        )
    }

    BeforeAll {
        # Returns the problems found in a unit test script text; an empty result means the frame is in place:
        # a top-level BeforeAll that calls Enable-SgtNetworkTripwire and then Assert-SgtNetworkTripwireActive,
        # a call to Disable-SgtNetworkTripwire, and Get-SgtUnmockedNetworkCall piped to Should.
        function Get-SgtTripwireFrameProblem {
            param([string]$ScriptText)
            $Problems = [System.Collections.Generic.List[string]]::new()
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$null, [ref]$null)
            $IsCommand = { param($n) $n -is [System.Management.Automation.Language.CommandAst] }

            $TopLevelBeforeAll = @(
                foreach ($Statement in $Ast.EndBlock.Statements) {
                    if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and $Statement.PipelineElements.Count -eq 1) {
                        $Element = $Statement.PipelineElements[0]
                        if ($Element -is [System.Management.Automation.Language.CommandAst] -and $Element.GetCommandName() -eq 'BeforeAll') { $Element }
                    }
                }
            )
            $Enable = $null
            $Assert = $null
            foreach ($Block in $TopLevelBeforeAll) {
                foreach ($Command in $Block.FindAll($IsCommand, $true)) {
                    switch ($Command.GetCommandName()) {
                        'Enable-SgtNetworkTripwire' { if (-not $Enable) { $Enable = $Command } }
                        'Assert-SgtNetworkTripwireActive' { if (-not $Assert) { $Assert = $Command } }
                    }
                }
            }
            if (-not $Enable) { $Problems.Add('Enable-SgtNetworkTripwire is not called in a top-level BeforeAll') }
            if (-not $Assert) { $Problems.Add('Assert-SgtNetworkTripwireActive is not called in a top-level BeforeAll') }
            if ($Enable -and $Assert -and $Assert.Extent.StartOffset -lt $Enable.Extent.StartOffset) {
                $Problems.Add('Assert-SgtNetworkTripwireActive comes before Enable-SgtNetworkTripwire')
            }

            $Names = @($Ast.FindAll($IsCommand, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
            if ($Names -notcontains 'Disable-SgtNetworkTripwire') { $Problems.Add('Disable-SgtNetworkTripwire is not called') }

            $Piped = @(
                $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.PipelineAst] }, $true) | Where-Object {
                    $Elements = $_.PipelineElements
                    $Elements.Count -ge 2 -and
                    $Elements[0] -is [System.Management.Automation.Language.CommandAst] -and $Elements[0].GetCommandName() -eq 'Get-SgtUnmockedNetworkCall' -and
                    $Elements[1] -is [System.Management.Automation.Language.CommandAst] -and $Elements[1].GetCommandName() -eq 'Should'
                }
            )
            if ($Piped.Count -eq 0) { $Problems.Add('Get-SgtUnmockedNetworkCall is not piped to Should') }
            , $Problems.ToArray()
        }
    }

    It 'Uses the tripwire frame in <Name>' -ForEach $script:Files {
        $Problems = Get-SgtTripwireFrameProblem -ScriptText (Get-Content -Path $Path -Raw)
        $Problems | Should -BeNullOrEmpty -Because ($Problems -join '; ')
    }

    It 'Accepts a script text that has the frame (positive fixture)' {
        $Text = @'
BeforeAll {
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
}
AfterAll { Disable-SgtNetworkTripwire }
Describe 'x' { It 'y' { Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty } }
'@
        $Problems = Get-SgtTripwireFrameProblem -ScriptText $Text
        $Problems | Should -BeNullOrEmpty -Because ($Problems -join '; ')
    }

    It 'Reports a script text that omits the frame (negative fixture)' {
        $Text = @'
Describe 'x' {
    BeforeAll { Enable-SgtNetworkTripwire }
    It 'y' { Get-SgtUnmockedNetworkCall; $true | Should -BeTrue }
}
'@
        $Problems = Get-SgtTripwireFrameProblem -ScriptText $Text
        $Problems | Should -Contain 'Enable-SgtNetworkTripwire is not called in a top-level BeforeAll'
        $Problems | Should -Contain 'Assert-SgtNetworkTripwireActive is not called in a top-level BeforeAll'
        $Problems | Should -Contain 'Disable-SgtNetworkTripwire is not called'
        $Problems | Should -Contain 'Get-SgtUnmockedNetworkCall is not piped to Should'
    }
}
