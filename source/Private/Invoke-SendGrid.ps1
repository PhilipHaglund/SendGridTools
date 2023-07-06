<#
.SYNOPSIS
This function is used to interact with the SendGrid API.

.DESCRIPTION
Invoke-SendGrid is a custom function designed to interact with the SendGrid API. It requires an active PSSendGridSession, which should be established via the Connect-SendGrid cmdlet before calling this function.

.PARAMETER Method
The web request method to use (GET, POST, PUT, DELETE etc).

.PARAMETER Namespace
The endpoint of the SendGrid API to interact with.

.PARAMETER ContentBody
(Optional) A hashtable containing the request body to send with the request.

.EXAMPLE
Invoke-SendGrid -Method GET -Namespace "mail/send"

#>
function Invoke-SendGrid {
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # The web request method.
        [Parameter(
            Mandatory,
            HelpMessage = 'The web request method.'
        )]
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

        # The endpoint to use.
        [Parameter(
            Mandatory,
            HelpMessage = 'The SendGrid endpoint to use.'
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        # The content body to send with the request.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [hashtable]$ContentBody
    )
    begin {
        # Function to get unique properties of an object.
        function Get-UniqueProperties {
            param (
                [Parameter(
                    Mandatory
                )]
                [object[]]$InputObject
            )
            # Get the properties of each object in the input array.
            $Members = foreach ($Object in $InputObject) {
                $Object | Get-Member -MemberType NoteProperty
            }
            # Return the unique properties.
            ($Members | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
        }
    }
    process {
        if ($PSCmdlet.ShouldProcess("$Method : $Namespace")) {
            Write-Verbose "Starting process with method: $Method and namespace: $Namespace"
            # Check if session is not a PSSendGridSession.
            if ($script:Session -isnot [PSSendGridSession]) {
                throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            }
            try {
                Write-Verbose 'Attempting to invoke query'
                # Invoke the query based on provided parameters.
                if ($PSBoundParameters.ContainsKey('ContentBody')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody)
                }
                else {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace)
                }
            }
            catch {
                throw $_.Exception.Message
            }

            # Get unique properties.
            $Properties = Get-UniqueProperties -InputObject $Query
            
            # Handle PSObject array with a single 'Result' property.
            if ($Query -is [System.Management.Automation.PSObject[]] -and $Properties -eq 'Result' -and $Properties.Count -eq 1) {
                $Query = $Query.result
                $Properties = Get-UniqueProperties -InputObject $Query
            }

            # Process each object in the query.
            foreach ($Object in $Query) {
                # Create a new custom object.
                [PSCustomObject]$PSObject = [PSCustomObject]::new()

                # Process each property in the properties array.
                foreach ($Property in $Properties) {
                    # Check for inline properties.
                    if ($Object.$Property -is [System.Management.Automation.PSCustomObject]) {
                        $InlineProperties = Get-UniqueProperties -InputObject $Object.$Property

                        # Process each inline property.
                        foreach ($InlineProperty in $InlineProperties) {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ('{0}{1}' -f ($Property -replace '[\s_-]+'), $($InlineProperty -replace '[\s_-]+'))  -Value $Object.$Property.$InlineProperty
                        }
                    }

                    # Switch based on the property type.
                    switch ($Object.$Property) {
                        { $_ -is [int64] -and $Property -match 'valid' } {
                            $PSObject | Add-Member -MemberType NoteProperty -Name ($Property -replace '[\s_-]+')  -Value ((Get-Date -Date '01-01-1970') + ([System.TimeSpan]::FromSeconds(($_))))
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