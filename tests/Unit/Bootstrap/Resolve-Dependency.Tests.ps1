BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive

    # Find the function by AST and define it from its text. Running Resolve-Dependency.ps1 itself would bootstrap and download.
    $script:ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../Resolve-Dependency.ps1'
    $script:ScriptAst = [System.Management.Automation.Language.Parser]::ParseFile((Convert-Path -Path $script:ScriptPath), [ref]$null, [ref]$null)
    $Found = @($script:ScriptAst.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Save-PSResourceWithRetry'
            }, $true))
    if ($Found.Count -ne 1)
    {
        throw ('Expected exactly one function Save-PSResourceWithRetry in Resolve-Dependency.ps1, found {0}.' -f $Found.Count)
    }
    $script:Function = $Found[0]
    . ([scriptblock]::Create($script:Function.Extent.Text))

    # A function outranks the real cmdlet, so a missing mock throws instead of downloading anything.
    function Save-PSResource
    {
        [CmdletBinding()]
        param([string]$Name, [string]$Version, [string]$Path, [switch]$TrustRepository, [switch]$Confirm, [string]$Repository)
        throw 'Save-PSResource stub reached: the mock is missing.'
    }

    Mock Start-Sleep {}

    $script:Parameter = @{ Path = 'TestDrive:\modules'; TrustRepository = $true; Confirm = $false; Name = 'Placeholder.Module'; Version = '1.2.3' }
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'Save-PSResourceWithRetry' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:Thrown = [System.Collections.Generic.List[object]]::new()
    }

    It 'saves once and warns nothing when the first attempt succeeds' {
        Mock Save-PSResource { $Copy = @{}; foreach ($Key in $PesterBoundParameters.Keys) { $Copy[$Key] = $PesterBoundParameters[$Key] }; $script:Calls.Add($Copy) }

        $Out = @(Save-PSResourceWithRetry -Parameter $script:Parameter -WarningVariable w -WarningAction SilentlyContinue)

        $script:Calls.Count | Should -Be 1
        @($w).Count | Should -Be 0
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $Out.Count | Should -Be 0
    }

    It 'tries again once after one failure' {
        Mock Save-PSResource {
            $Copy = @{}; foreach ($Key in $PesterBoundParameters.Keys) { $Copy[$Key] = $PesterBoundParameters[$Key] }; $script:Calls.Add($Copy)
            if ($script:Calls.Count -eq 1)
            {
                throw [System.NullReferenceException]::new('placeholder')
            }
        }

        $Out = @(Save-PSResourceWithRetry -Parameter $script:Parameter -WarningVariable w -WarningAction SilentlyContinue)

        $script:Calls.Count | Should -Be 2
        @($w).Count | Should -Be 1
        $w[0].Message | Should -BeLike '*Placeholder.Module*'
        $w[0].Message | Should -BeLike '*System.NullReferenceException*'
        $w[0].Message | Should -BeLike '*attempt 1 of 3*'
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -ge 1 -and $Seconds -le 10 }
        Should -Invoke Start-Sleep -Times 1 -Exactly
        $Out.Count | Should -Be 0
    }

    It 'throws the last error unchanged after three failures' {
        Mock Save-PSResource {
            $Copy = @{}; foreach ($Key in $PesterBoundParameters.Keys) { $Copy[$Key] = $PesterBoundParameters[$Key] }; $script:Calls.Add($Copy)
            $Exception = [System.InvalidOperationException]::new('placeholder')
            $script:Thrown.Add($Exception)
            throw $Exception
        }

        $Caught = $null
        try
        {
            Save-PSResourceWithRetry -Parameter $script:Parameter -WarningVariable w -WarningAction SilentlyContinue
        }
        catch
        {
            $Caught = $_
        }

        $script:Calls.Count | Should -Be 3
        $Caught | Should -Not -BeNullOrEmpty
        [object]::ReferenceEquals($Caught.Exception, $script:Thrown[2]) | Should -BeTrue
        @($w).Count | Should -Be 2
        $w[0].Message | Should -BeLike '*attempt 1 of 3*'
        $w[1].Message | Should -BeLike '*attempt 2 of 3*'
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'passes today''s parameters to every attempt' {
        Mock Save-PSResource {
            $Copy = @{}; foreach ($Key in $PesterBoundParameters.Keys) { $Copy[$Key] = $PesterBoundParameters[$Key] }; $script:Calls.Add($Copy)
            if ($script:Calls.Count -lt 3)
            {
                throw [System.NullReferenceException]::new('placeholder')
            }
        }

        $null = Save-PSResourceWithRetry -Parameter $script:Parameter -WarningAction SilentlyContinue

        $script:Calls.Count | Should -Be 3
        # Confirm is a real parameter of the call here, so it is not in this list.
        $Common = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf')
        foreach ($Call in $script:Calls)
        {
            $Keys = @($Call.Keys | Where-Object { $_ -notin $Common } | Sort-Object)
            ($Keys -join ',') | Should -Be 'Confirm,Name,Path,TrustRepository,Version'
            $Call.ContainsKey('Repository') | Should -BeFalse
            foreach ($Key in $Keys)
            {
                $Call[$Key] | Should -Be $script:Parameter[$Key]
            }
        }
    }

    It 'returns a non-terminating error without trying again' {
        Mock Save-PSResource {
            $Copy = @{}; foreach ($Key in $PesterBoundParameters.Keys) { $Copy[$Key] = $PesterBoundParameters[$Key] }; $script:Calls.Add($Copy)
            Write-Error 'placeholder non-terminating'
        }

        $ErrorActionPreference = 'Continue'
        $Out = @(Save-PSResourceWithRetry -Parameter $script:Parameter -WarningVariable w -WarningAction SilentlyContinue 2>$null)

        $script:Calls.Count | Should -Be 1
        @($w).Count | Should -Be 0
        $Out.Count | Should -Be 1
        $Out[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
    }

    It 'tries a non-terminating error three times when ErrorActionPreference is Stop' {
        Mock Save-PSResource {
            $Copy = @{}; foreach ($Key in $PesterBoundParameters.Keys) { $Copy[$Key] = $PesterBoundParameters[$Key] }; $script:Calls.Add($Copy)
            Write-Error 'placeholder non-terminating'
        }

        $Caught = $null
        $ErrorActionPreference = 'Stop'
        try
        {
            Save-PSResourceWithRetry -Parameter $script:Parameter -WarningVariable w -WarningAction SilentlyContinue
        }
        catch
        {
            $Caught = $_
        }

        $script:Calls.Count | Should -Be 3
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.Exception | Should -BeOfType [Microsoft.PowerShell.Commands.WriteErrorException]
        $Caught.Exception.Message | Should -Be 'placeholder non-terminating'
        @($w).Count | Should -Be 2
        $w[0].Message | Should -BeLike '*Placeholder.Module*'
        $w[0].Message | Should -BeLike '*attempt 1 of 3*'
        $w[1].Message | Should -BeLike '*Placeholder.Module*'
        $w[1].Message | Should -BeLike '*attempt 2 of 3*'
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'calls Save-PSResource only inside the function, with today''s parameters' {
        $SaveCalls = @($script:ScriptAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Save-PSResource'
                }, $true))
        $Inside = @($SaveCalls | Where-Object { $_.Extent.StartOffset -gt $script:Function.Extent.StartOffset -and $_.Extent.EndOffset -lt $script:Function.Extent.EndOffset })
        $Outside = @($SaveCalls | Where-Object { $_ -notin $Inside })
        $Inside.Count | Should -Be 1
        # The only other call is the PowerShellGet bootstrap one, which this change does not touch.
        $Outside.Count | Should -Be 1
        $Outside[0].Extent.Text | Should -BeLike '*@savePowerShellGetParameters*'

        $Callers = @($script:ScriptAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Save-PSResourceWithRetry'
                }, $true))
        $Callers.Count | Should -Be 1
        $Assignment = $Callers[0].Parent.Parent
        $Assignment.Extent.Text | Should -Be '$savePSResourceError = Save-PSResourceWithRetry -Parameter $savePSResourceParameters'
    }

    It 'reaches no network' {
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
