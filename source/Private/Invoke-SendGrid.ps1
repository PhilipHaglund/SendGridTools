function Invoke-SendGrid {
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        [Parameter(
            Mandatory
        )]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [Parameter(
            Mandatory
        )]
        [string]$Namespace,

        [Parameter()]
        [hashtable]$ContentBody
    )
    begin {
        function Get-UniqueProperties {
            param (
                [Parameter(
                    Mandatory
                )]
                [object[]]$InputObject
            )
            $Members = foreach ($Object in $InputObject) {
                $Object | Get-Member -MemberType NoteProperty
            }
            ($Members | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
        }

    }
    process {
        if ($PSCmdlet.ShouldProcess("$Method : $Namespace")) {
            if ($script:Session -isnot [PSSendGridSession]) {
                throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            }
            try {
                if ($PSBoundParameters.ContainsKey('ContentBody')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody)
                }
                else {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace)
                }
            }
            catch {
                asd
            }
            #$Members = foreach ($Response in $Query) {
            #    $Response | Get-Member -MemberType NoteProperty
            #}
            #$Properties = ($Members | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
            $Properties = Get-UniqueProperties -InputObject $Query

            foreach ($Object in $Query) {
                [PSCustomObject]$PSObject = [PSCustomObject]::new()
                foreach ($Property in $Properties) {
                    if ($Object.$Property -is [System.Management.Automation.PSCustomObject]) {
                        #$InlineMembers = $Object.$Property | Get-Member -MemberType NoteProperty
                        #$InlineProperties = ($InlineMembers | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
                        $InlineProperties = Get-UniqueProperties -InputObject $Object.$Property
                        foreach ($InlineProperty in $InlineProperties) {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ('{0}{1}' -f ($Property -replace '[\s_-]+'), $($InlineProperty -replace '[\s_-]+'))  -Value $Object.$Property.$InlineProperty
                        }
                    }
                    
                    switch ($Object.$Property) {
                        { $_ -is [int64] -and $Property -match 'valid' } {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ($Property -replace '[\s_-]+')  -Value ((Get-Date -Date '01-01-1970') + ([System.TimeSpan]::FromSeconds(($_))))
                            break
                        }
                        { $_ -is [System.Object[]] -and $Property -match 'result' } {
                            #$NestedProperties = Get-UniqueProperties -InputObject $Object.$Property
                            foreach ($NestedMember in $_) {
                                #$NestedMembers = $NestedObject | Get-Member -MemberType NoteProperty
                                $NestedProperties = Get-UniqueProperties -InputObject $Object.$Property
                                foreach ($NestedProperty in $NestedProperties) {
                                    #$NestedPropertyName = ($NestedProperty.Name -replace '[\s_-]+') | ConvertTo-TitleCase
                                    #$NestedPropertyValue = $NestedObject.$($NestedMember.Name)
                                    $PSObject | Add-Member -MemberType NoteProperty -Name ($NestedProperty -replace '[\s_-]+') -Value ($NestedMember.$NestedProperty) -Force
                                }
                            }
                            break
                        }
                        Default {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ($Property -replace '[\s_-]+') -Value $Object.$Property -Force
                            break
                        }
                    }
                }

                $PSObject
            }
        }
    }
}