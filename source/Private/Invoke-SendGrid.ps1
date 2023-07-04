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
    process {
        if ($PSCmdlet.ShouldProcess("$Method : $Namespace")) {
            if ($PSBoundParameters.ContainsKey('ContentBody')) {
                $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody)
            }
            else {
                $Query = $script:Session.InvokeQuery($Method, $Namespace)
            }
            $Members = foreach ($Response in $Query) {
                $Response | Get-Member -MemberType NoteProperty
            }
            $Properties = ($Members | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
        
            foreach ($Object in $Query) {
                [PSCustomObject]$PSObject = [PSCustomObject]::new()
                foreach ($Property in $Properties) {
                    if ($Object.$Property -is [System.Management.Automation.PSCustomObject]) {
                        $InlineMembers = $Object.$Property | Get-Member -MemberType NoteProperty
                        $InlineProperties = ($InlineMembers | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
                        foreach ($InlineProperty in $InlineProperties) {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ('{0}{1}' -f ($Property -replace '[\s_-]+'), $($InlineProperty -replace '[\s_-]+'))  -Value $Object.$Property.$InlineProperty
                        }
                    
                    }
                    switch ($Object.$Property) {
                        { $_ -is [int64] -and $Property -match 'valid' } {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ($Property -replace '[\s_-]+')  -Value ((Get-Date -Date '01-01-1970') + ([System.TimeSpan]::FromSeconds(($_))))
                            break
                        }
                        Default {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ($Property -replace '[\s_-]+')  -Value $Object.$Property -Force
                            break
                        }
                    }
                }

                $PSObject
            }
        }
    }
}