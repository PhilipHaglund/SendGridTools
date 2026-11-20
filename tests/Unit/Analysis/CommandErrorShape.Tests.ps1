BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive

    $script:PublicPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../source/Public')).Path
    $script:FixturePath = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/CommandErrorText.e155c0c.txt'
    # The six catch blocks that only return: five tab completers in Get-SGEmailActivity and one in New-SGAuthenticatedDomain.
    $script:ExpectedReturn = @(
        'Get-SGEmailActivity.ps1'
        'Get-SGEmailActivity.ps1'
        'Get-SGEmailActivity.ps1'
        'Get-SGEmailActivity.ps1'
        'Get-SGEmailActivity.ps1'
        'New-SGAuthenticatedDomain.ps1'
    )

    function script:Get-SgtArgumentText {
        # The text of the argument given to a named parameter of a command: the attached argument or the next element.
        param($Command, [string]$Name)
        $Elements = $Command.CommandElements
        for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
            $Element = $Elements[$Index]
            if ($Element -is [System.Management.Automation.Language.CommandParameterAst] -and $Element.ParameterName -eq $Name) {
                if ($null -ne $Element.Argument) { return $Element.Argument }
                if ($Index + 1 -lt $Elements.Count) { return $Elements[$Index + 1] }
            }
        }
        $null
    }

    function script:Get-SgtCatchWalk {
        # One record per CatchClauseAst under source/Public, files in ordinal order and catch blocks in file order.
        [string[]]$Paths = @(Get-ChildItem -LiteralPath $script:PublicPath -Filter '*.ps1' -Recurse -File | ForEach-Object { $_.FullName })
        [System.Array]::Sort($Paths, [System.StringComparer]::Ordinal)
        $script:WalkedFileCount = $Paths.Count
        foreach ($Path in $Paths) {
            $Relative = $Path.Substring($script:PublicPath.Length).TrimStart('\', '/') -replace '\\', '/'
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
            $Catches = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CatchClauseAst] }, $true))
            foreach ($Catch in $Catches) {
                $WriteError = @($Catch.Body.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Write-Error' }, $true))
                $Statements = @($Catch.Body.Statements)
                $OnlyReturn = $Statements.Count -eq 1 -and $Statements[0] -is [System.Management.Automation.Language.ReturnStatementAst]
                [pscustomobject]@{ File = $Relative; Line = $Catch.Extent.StartLineNumber; OnlyReturn = $OnlyReturn; WriteError = $WriteError }
            }
        }
    }

    function script:Get-SgtShapeViolation {
        # Returns a text for every Write-Error in a catch block that is not Write-Error -Exception (ConvertTo-SendGridCommandException ... -ErrorRecord $_).
        param($Walk)
        foreach ($Block in $Walk | Where-Object { -not $_.OnlyReturn }) {
            foreach ($Command in $Block.WriteError) {
                $Where = '{0}:{1}' -f $Block.File, $Block.Line
                $Elements = $Command.CommandElements
                $Skip = @{}
                for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                    $Element = $Elements[$Index]
                    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
                        if ($Element.ParameterName -eq 'Message') { "$Where has -Message" }
                        if ($null -eq $Element.Argument) { $Skip[$Index + 1] = $true }
                    }
                    elseif (-not $Skip.ContainsKey($Index)) {
                        "$Where has a positional argument"
                    }
                }
                $Argument = Get-SgtArgumentText -Command $Command -Name 'Exception'
                if ($null -eq $Argument) { "$Where has no -Exception"; continue }
                $Inner = if ($Argument -is [System.Management.Automation.Language.ParenExpressionAst]) { $Argument.Pipeline } else { $null }
                $Call = if ($null -ne $Inner -and $Inner.PipelineElements.Count -eq 1) { $Inner.PipelineElements[0] } else { $null }
                if ($Call -isnot [System.Management.Automation.Language.CommandAst] -or $Call.GetCommandName() -ne 'ConvertTo-SendGridCommandException') {
                    "$Where -Exception is not a ConvertTo-SendGridCommandException call"
                    continue
                }
                $Record = Get-SgtArgumentText -Command $Call -Name 'ErrorRecord'
                if ($Record -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $Record.VariablePath.UserPath -ne '_') {
                    "$Where does not pass -ErrorRecord `$_"
                }
                if ($null -eq (Get-SgtArgumentText -Command $Call -Name 'Message')) { "$Where passes no -Message to the helper" }
            }
        }
    }
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'Command error shape (D133)' {
    BeforeAll {
        $script:Walk = @(Get-SgtCatchWalk)
    }

    It 'Walks every file under source/Public' {
        $Files = @(Get-ChildItem -LiteralPath $script:PublicPath -Filter '*.ps1' -Recurse -File)
        $Files.Count | Should -BeGreaterThan 0
        $script:WalkedFileCount | Should -Be $Files.Count
        # Every file parses without error, so the walk saw all its catch blocks.
        foreach ($File in $Files) {
            $Errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$Errors)
            @($Errors).Count | Should -Be 0 -Because "$($File.Name) must parse"
        }
    }

    It 'Finds at least 82 catch blocks that write an error' {
        @($script:Walk | Where-Object { $_.WriteError.Count -gt 0 }).Count | Should -BeGreaterOrEqual 82
    }

    It 'Has exactly the six return-only catch blocks of the tab completers' {
        $Returns = @($script:Walk | Where-Object { $_.OnlyReturn })
        $Returns.Count | Should -Be 6
        ($Returns.File -join ',') | Should -BeExactly ($script:ExpectedReturn -join ',')
    }

    It 'Has no catch block that neither returns nor writes an error' {
        @($script:Walk | Where-Object { -not $_.OnlyReturn -and $_.WriteError.Count -eq 0 } | ForEach-Object { '{0}:{1}' -f $_.File, $_.Line }) | Should -BeNullOrEmpty
    }

    It 'Writes every error as Write-Error -Exception (ConvertTo-SendGridCommandException ... -ErrorRecord $_)' {
        @(Get-SgtShapeViolation -Walk $script:Walk) | Should -BeNullOrEmpty
    }

    It 'Catches the old shape: Write-Error -Message in a catch block is a violation' {
        # The checker is run on text held in memory, so it can fail.
        $Text = 'try { 1 } catch { Write-Error -Message (''Failed. {0}'' -f $_.Exception.Message) -ErrorAction Stop }'
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $Catch = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
        $WriteError = @($Catch.Body.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Write-Error' }, $true))
        $Fake = [pscustomobject]@{ File = 'memory.ps1'; Line = 1; OnlyReturn = $false; WriteError = $WriteError }
        @(Get-SgtShapeViolation -Walk @($Fake)).Count | Should -BeGreaterThan 0
    }

    It 'Keeps the text of every command error as at e155c0c' {
        $Expected = @(Get-Content -LiteralPath $script:FixturePath)
        $Actual = foreach ($Block in $script:Walk | Where-Object { -not $_.OnlyReturn }) {
            foreach ($Command in $Block.WriteError) {
                $Exception = Get-SgtArgumentText -Command $Command -Name 'Exception'
                $Call = $Exception.Pipeline.PipelineElements[0]
                '{0}|{1}' -f $Block.File, (Get-SgtArgumentText -Command $Call -Name 'Message').Extent.Text
            }
        }
        $Actual = @($Actual)
        $Actual.Count | Should -Be $Expected.Count
        for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
            $Actual[$Index] | Should -BeExactly $Expected[$Index]
        }
    }

    It 'Has one fixture line that differs from e155c0c on purpose: Disconnect-SendGrid writes the exception text, not the script block' {
        # At e155c0c the line held: ('Unable to disconnect from SendGrid. {0}' -f { $_.Exception.Message })
        # D133 changes it to the exception text, so this one fixture line is the new expression.
        $Line = @(Get-Content -LiteralPath $script:FixturePath | Where-Object { $_ -like 'Disconnect-SendGrid.ps1|*' })
        $Line.Count | Should -Be 1
        $Line[0] | Should -BeExactly 'Disconnect-SendGrid.ps1|(''Unable to disconnect from SendGrid. {0}'' -f $_.Exception.Message)'
    }

    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
