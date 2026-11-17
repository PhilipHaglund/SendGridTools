function Remove-EmptyHashtable {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper that only edits the caller-supplied hashtable in memory and changes no system state; SupportsShouldProcess would add -WhatIf and -Confirm and change behaviour, so the repair is deferred.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '', Justification = 'The body reads the pipeline-bound parameter once instead of per piped object; moving it into a process block would change how piped input is handled, so the repair is deferred.')]
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [alias('Splat', 'IDictionary')]
        [System.Collections.IDictionary[]]$Hashtable,
        [string[]] $ExcludeParameter,
        [switch] $Recursive,
        [int] $Rerun,
        [switch]$DoNotRemoveNull,
        [switch]$DoNotRemoveEmpty,
        [switch]$DoNotRemoveEmptyArray,
        [switch]$DoNotRemoveEmptyDictionary
    )
    foreach ($Hash in $Hashtable) {
        foreach ($Key in [object[]]$Hash.Keys) {
            if ($Key -notin $ExcludeParameter) {
                if ($Recursive) {
                    if ($Hash[$Key] -is [System.Collections.IDictionary]) {
                        if ($Hash[$Key].Count -eq 0) {
                            if (-not $DoNotRemoveEmptyDictionary) {
                                $Hash.Remove($Key)
                            }
                        }
                        else {
                            Remove-EmptyHashtable -Hashtable $Hash[$Key] -Recursive:$Recursive
                        }
                    }
                    else {
                        if (-not $DoNotRemoveNull -and $null -eq $Hash[$Key]) {
                            Write-Verbose -Message "Removing $Key from hashtable, because it is null."
                            $Hash.Remove($Key)
                        }
                        elseif (-not $DoNotRemoveEmpty -and $Hash[$Key] -is [string] -and $Hash[$Key] -eq '') {
                            Write-Verbose -Message "Removing $Key from hashtable, because it is empty."
                            $Hash.Remove($Key)
                        }
                        elseif (-not $DoNotRemoveEmptyArray -and $Hash[$Key] -is [System.Collections.IList] -and $Hash[$Key].Count -eq 0) {
                            Write-Verbose -Message "Removing $Key from hashtable, because it is an empty array."
                            $Hash.Remove($Key)
                        }
                    }
                }
                else {
                    if (-not $DoNotRemoveNull -and $null -eq $Hash[$Key]) {
                        Write-Verbose -Message "Removing $Key from hashtable, because it is null."
                        $Hash.Remove($Key)
                    }
                    elseif (-not $DoNotRemoveEmpty -and $Hash[$Key] -is [string] -and $Hash[$Key] -eq '') {
                        Write-Verbose -Message "Removing $Key from hashtable, because it is empty."
                        $Hash.Remove($Key)
                    }
                    elseif (-not $DoNotRemoveEmptyArray -and $Hash[$Key] -is [System.Collections.IList] -and $Hash[$Key].Count -eq 0) {
                        Write-Verbose -Message "Removing $Key from hashtable, because it is an empty array."
                        $Hash.Remove($Key)
                    }
                }
            }
        }
    }
    if ($Rerun) {
        for ($i = 0; $i -lt $Rerun; $i++) {
            Remove-EmptyHashtable -Hashtable $Hash -Recursive:$Recursive
        }
    }
}