BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    InModuleScope SendGridTools {
        function Script:New-SgtCaughtRecord {
            # Builds the ErrorRecord a command's catch block sees: the exception, optionally with the session's Data keys,
            # optionally wrapped in outer exceptions.
            param([System.Exception]$Exception, [string[]]$Wrap = @())
            $Current = $Exception
            foreach ($Text in $Wrap) { $Current = [System.InvalidOperationException]::new($Text, $Current) }
            [System.Management.Automation.ErrorRecord]::new($Current, 'made-up-id', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtCaughtRecord' -ErrorAction SilentlyContinue
    }
    Disable-SgtNetworkTripwire
}

Describe 'ConvertTo-SendGridCommandException' {
    It 'Returns a WriteErrorException with the given text' {
        InModuleScope SendGridTools {
            $Record = New-SgtCaughtRecord -Exception ([System.Management.Automation.RuntimeException]::new('made-up cause'))
            $Result = ConvertTo-SendGridCommandException -Message 'Failed to do a thing. made-up cause' -ErrorRecord $Record
            $Result | Should -BeOfType [Microsoft.PowerShell.Commands.WriteErrorException]
            $Result.Message | Should -BeExactly 'Failed to do a thing. made-up cause'
        }
    }

    It 'Keeps the caught exception itself as InnerException' {
        InModuleScope SendGridTools {
            $Caught = [System.Management.Automation.RuntimeException]::new('made-up cause')
            $Record = New-SgtCaughtRecord -Exception $Caught
            $Result = ConvertTo-SendGridCommandException -Message 'text' -ErrorRecord $Record
            [object]::ReferenceEquals($Result.InnerException, $Caught) | Should -BeTrue
        }
    }

    It 'Copies StatusCode and SendGridErrors from the caught exception' {
        InModuleScope SendGridTools {
            $Caught = [System.Management.Automation.RuntimeException]::new('made-up cause')
            $Errors = [object[]]@([pscustomobject]@{ Field = 'name'; Message = 'name is required' })
            $Caught.Data['StatusCode'] = 400
            $Caught.Data['SendGridErrors'] = $Errors
            $Result = ConvertTo-SendGridCommandException -Message 'text' -ErrorRecord (New-SgtCaughtRecord -Exception $Caught)
            $Result.Data['StatusCode'] | Should -Be 400
            $Result.Data['StatusCode'] | Should -BeOfType [int]
            @($Result.Data['SendGridErrors']).Count | Should -Be 1
            @($Result.Data['SendGridErrors'])[0].Field | Should -BeExactly 'name'
            @($Result.Data['SendGridErrors'])[0].Message | Should -BeExactly 'name is required'
        }
    }

    It 'Copies the Data from deeper in the chain when the caught exception has none' {
        InModuleScope SendGridTools {
            $Deep = [System.Management.Automation.RuntimeException]::new('made-up deep cause')
            $Deep.Data['StatusCode'] = 404
            $Deep.Data['SendGridErrors'] = [object[]]@([pscustomobject]@{ Field = $null; Message = 'resource not found' })
            $Record = New-SgtCaughtRecord -Exception $Deep -Wrap 'made-up middle', 'made-up outer'
            $Result = ConvertTo-SendGridCommandException -Message 'text' -ErrorRecord $Record
            $Result.Data['StatusCode'] | Should -Be 404
            @($Result.Data['SendGridErrors'])[0].Message | Should -BeExactly 'resource not found'
            $Result.InnerException.Message | Should -BeExactly 'made-up outer'
        }
    }

    It 'Takes each key from the first exception in the chain that holds it' {
        InModuleScope SendGridTools {
            $Deep = [System.Management.Automation.RuntimeException]::new('made-up deep cause')
            $Deep.Data['StatusCode'] = 500
            $Deep.Data['SendGridErrors'] = [object[]]@([pscustomobject]@{ Field = $null; Message = 'deep error' })
            $Near = [System.InvalidOperationException]::new('made-up near cause', $Deep)
            $Near.Data['StatusCode'] = 401
            $Result = ConvertTo-SendGridCommandException -Message 'text' -ErrorRecord (New-SgtCaughtRecord -Exception $Near)
            $Result.Data['StatusCode'] | Should -Be 401
            @($Result.Data['SendGridErrors'])[0].Message | Should -BeExactly 'deep error'
        }
    }

    It 'Gives no Data keys when no exception in the chain holds any' {
        InModuleScope SendGridTools {
            $Record = New-SgtCaughtRecord -Exception ([System.Management.Automation.RuntimeException]::new('made-up cause')) -Wrap 'made-up outer'
            $Result = ConvertTo-SendGridCommandException -Message 'text' -ErrorRecord $Record
            $Result.Data.Count | Should -Be 0
            $Result.Data.Contains('StatusCode') | Should -BeFalse
            $Result.Data.Contains('SendGridErrors') | Should -BeFalse
        }
    }

    It 'Copies only the key that exists' {
        InModuleScope SendGridTools {
            $Caught = [System.Management.Automation.RuntimeException]::new('made-up cause')
            $Caught.Data['StatusCode'] = 502
            $Result = ConvertTo-SendGridCommandException -Message 'text' -ErrorRecord (New-SgtCaughtRecord -Exception $Caught)
            $Result.Data.Contains('StatusCode') | Should -BeTrue
            $Result.Data.Contains('SendGridErrors') | Should -BeFalse
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
