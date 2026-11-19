BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
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

BeforeDiscovery {
    $script:KeyAnswer = '{"api_key_id":"placeholder-id","name":"placeholder-name","scopes":["alerts.read"]}'
    $script:DomainAnswer = '{"id":1001,"subdomain":"sgt-test-sub","domain":"example.com","valid":false}'
    $script:ReadCase = @(
        @{ Command = 'Set-SGApiKey'; Call = 'Set-SGApiKey -UniqueId ''placeholder-id'' -Scopes ''mail.send'''; Answer = $script:KeyAnswer; Name = 'placeholder-name'; Id = 'placeholder-id' }
        @{ Command = 'Remove-SGApiKey'; Call = 'Remove-SGApiKey -UniqueId ''placeholder-id'''; Answer = $script:KeyAnswer; Name = 'placeholder-name'; Id = 'placeholder-id' }
        @{ Command = 'Confirm-SGAuthenticatedDomain'; Call = 'Confirm-SGAuthenticatedDomain -UniqueId ''1001'''; Answer = $script:DomainAnswer; Name = 'sgt-test-sub.example.com'; Id = '1001' }
        @{ Command = 'Remove-SGAuthenticatedDomain'; Call = 'Remove-SGAuthenticatedDomain -UniqueId ''1001'''; Answer = $script:DomainAnswer; Name = 'sgt-test-sub.example.com'; Id = '1001' }
        @{ Command = 'Confirm-SGBrandedDomainLink'; Call = 'Confirm-SGBrandedDomainLink -UniqueId ''1001'''; Answer = $script:DomainAnswer; Name = 'sgt-test-sub.example.com'; Id = '1001' }
        @{ Command = 'Remove-SGBrandedDomainLink'; Call = 'Remove-SGBrandedDomainLink -UniqueId ''1001'''; Answer = $script:DomainAnswer; Name = 'sgt-test-sub.example.com'; Id = '1001' }
        @{ Command = 'Set-SGAuthenticatedDomainToSubUser'; Call = 'Set-SGAuthenticatedDomainToSubUser -UniqueId ''1001'' -UserName ''sgt-test-subuser'''; Answer = $script:DomainAnswer; Name = 'sgt-test-sub.example.com'; Id = '1001' }
    )
}

# Sprint 4 step 5 measurements (M1-M4). Each It writes one MEASURE line with command names, counts, type names and
# True/False only, and asserts nothing about the measured value, so the same file measures any version of the
# module. M1 and M2 run in a new process whose host counts the choice prompts and answers Yes at once (no console
# is read); the tripwire's stub gives the same made-up answer to every request there.
Describe 'Sprint 4 step 5 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'M1: prompts for <Command> -Confirm' -ForEach $script:ReadCase {
        $Run = Invoke-SgtInCountingHost -Script ('$null = {0} -Confirm' -f $Call) -AnswerJson $Answer
        $Result = 'prompts {0}; requests {1}; threw {2}; unmocked calls {3}' -f $Run.PromptCount, $Run.NetworkCallCount, $Run.Threw, $Run.UnmockedCall.Count
        Write-Host ('MEASURE M1 [{0} {1}] {2} -Confirm: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M2: What if lines for <Command> -WhatIf' -ForEach $script:ReadCase {
        $Run = Invoke-SgtInCountingHost -Script ('$null = {0} -WhatIf' -f $Call) -AnswerJson $Answer
        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $Result = 'What if lines {0}; a line names a Get-SG command {1}; the name is in a line {2}; the id is in a line {3}; requests {4}; prompts {5}; threw {6}; unmocked calls {7}' -f $WhatIf.Count,
            (@($WhatIf | Where-Object { $_ -like '*"Get-SG*' }).Count -gt 0), (@($WhatIf | Where-Object { $_ -like ('*{0}*' -f $Name) }).Count -gt 0),
            (@($WhatIf | Where-Object { $_ -like ('*{0}*' -f $Id) }).Count -gt 0), $Run.NetworkCallCount, $Run.PromptCount, $Run.Threw, $Run.UnmockedCall.Count
        Write-Host ('MEASURE M2 [{0} {1}] {2} -WhatIf: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: the path <Command> sends for a+b@example.com' -ForEach @(
        @{ Command = 'Remove-SGBlock' }
        @{ Command = 'Remove-SGBounce' }
        @{ Command = 'Remove-SGInvalidEmail' }
        @{ Command = 'Remove-SGSpamReport' }
        @{ Command = 'Remove-SGGlobalSuppression' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $null = & $Command -EmailAddress 'a+b@example.com' -Confirm:$false
            $Calls = Get-SgtNetworkCall
            'requests {0}; method {1}; path {2}' -f $Calls.Count, $Calls[0].Method, $Calls[0].Uri.AbsolutePath
        }
        Write-Host ('MEASURE M3 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: the words Remove-SGBlock uses for <Name>' -ForEach @(
        @{ Name = 'one address under -WhatIf'; Script = 'Remove-SGBlock -EmailAddress ''a+b@example.com'' -WhatIf' }
        @{ Name = 'DeleteAll under -WhatIf'; Script = 'Remove-SGBlock -DeleteAll -WhatIf' }
    ) {
        $Run = Invoke-SgtInCountingHost -Script $Script
        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        # \b keeps the command name Remove-SGBlock out of the match.
        $Result = 'What if lines {0}; says block {1}; says bounce {2}' -f $WhatIf.Count, (@($WhatIf | Where-Object { $_ -match '\bblocks?\b' }).Count -gt 0), (@($WhatIf | Where-Object { $_ -match 'bounce' }).Count -gt 0)
        Write-Host ('MEASURE M3 [{0} {1}] Remove-SGBlock, {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: the words in the Remove-SGBlock error for <Name>' -ForEach @(
        @{ Name = 'one address' ; DeleteAll = $false }
        @{ Name = 'DeleteAll' ; DeleteAll = $true }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; DeleteAll = $DeleteAll } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw ([System.Exception]::new('sgt-test-transport-text'))
            $Caught = $null
            try {
                if ($DeleteAll) { $null = Remove-SGBlock -DeleteAll -Confirm:$false } else { $null = Remove-SGBlock -EmailAddress 'a+b@example.com' -Confirm:$false }
            }
            catch {
                $Caught = $_
            }
            'threw {0}; says block {1}; says bounce {2}' -f ($null -ne $Caught), ("$($Caught.Exception.Message)" -match '\bblocks?\b'), ("$($Caught.Exception.Message)" -match 'bounce')
        }
        Write-Host ('MEASURE M3 [{0} {1}] Remove-SGBlock error, {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M4: the type of AddedAt through Invoke-SendGrid for <Name>' -ForEach @(
        @{ Name = 'a value inside Int32'; Json = '{"added_at":1700000000}' }
        @{ Name = 'a value outside Int32'; Json = '{"added_at":3000000000}' }
        @{ Name = 'a list inside Int32'; Json = '{"added_at":[1700000000,1700000001]}' }
        @{ Name = 'a list with one value outside Int32'; Json = '{"added_at":[1700000000,3000000000]}' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Json = $Json } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ($Json | ConvertFrom-Json)
            $Caught = $null
            $Out = $null
            try {
                $Out = @(Invoke-SendGrid -Method Get -Namespace 'things')
            }
            catch {
                $Caught = $_
            }
            if ($Caught) {
                'threw True; error type {0}' -f $Caught.Exception.GetType().FullName
            }
            else {
                $Value = $Out[0].AddedAt
                $ElementType = (@($Value) | ForEach-Object { $_.GetType().FullName }) -join ','
                'threw False; type {0}; element types {1}' -f $Value.GetType().FullName, $ElementType
            }
        }
        Write-Host ('MEASURE M4 [{0} {1}] Invoke-SendGrid, {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M4: the type of AddedAt and UpdatedAt from Get-SGIPAddress -IncludeRegion' {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Item = '{"ip":"192.0.2.10","region":"us","added_at":1700000000,"updated_at":1700000001,"is_enabled":true}' | ConvertFrom-Json
            Set-SgtCursorNetworkStub -Page @(@{ Items = @($Item); AfterKey = $null })
            $Out = @(Get-SGIPAddress -IncludeRegion)
            'objects {0}; AddedAt type {1}; UpdatedAt type {2}; requests {3}' -f $Out.Count, $Out[0].AddedAt.GetType().FullName, $Out[0].UpdatedAt.GetType().FullName, (Get-SgtNetworkCall).Count
        }
        Write-Host ('MEASURE M4 [{0} {1}] Get-SGIPAddress -IncludeRegion: {2}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
