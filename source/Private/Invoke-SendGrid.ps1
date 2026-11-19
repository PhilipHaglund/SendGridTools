<#
.SYNOPSIS
This function is used to interact with the SendGrid API.

.DESCRIPTION
Invoke-SendGrid is a custom function designed to interact with the SendGrid API. It requires an active SendGridSession, which should be established via the Connect-SendGrid cmdlet before calling this function.

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
        SupportsShouldProcess,
        ConfirmImpact = 'None'
    )]
    param (
        # The web request method.
        [Parameter(
            Mandatory,
            HelpMessage = 'The web request method.',
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

        # The endpoint to use.
        [Parameter(
            Mandatory,
            HelpMessage = 'The SendGrid endpoint to use.',
            Position = 1
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        # The content body to send with the request.
        [Parameter(
            HelpMessage = 'The content body to send with the request.',
            Position = 2
        )]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [hashtable]$ContentBody,

        # The username of the subuser to send the query on behalf of.
        [Parameter(
            HelpMessage = 'The username of the subuser to send the query on behalf of.',
            Position = 3
        )]
        [ValidateNotNullOrEmpty()]
        [string]$OnBehalfOf,

        # The calling cmdlet or function that invoked this function.
        [Parameter(
            HelpMessage = 'The calling cmdlet or function that invoked this function.',
            Position = 4
        )]
        [ValidateNotNullOrEmpty()]
        [string]$CallingCmdlet
    )
    begin {
        # Function to get unique properties of an object.
        function Get-UniqueProperties {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Private inner helper; renaming it is kept out of this change that must not alter behaviour, so the repair is deferred.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '', Justification = 'The body reads the pipeline-bound parameter once instead of per piped object; moving it into a process block would change how piped input is handled, so the repair is deferred.')]
            param (
                [Parameter(
                    ValueFromPipeline
                )]
                [object[]]$InputObject
            )
            # Get the properties of each object in the input array.
            $Members = foreach ($Object in $InputObject) {
                $Object | Get-Member -MemberType NoteProperty
            }
            # Return the unique properties.
            if ($null -ne $Members) {
                ($Members | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
            }
        }
    }
    process {
        if ($PSCmdlet.ShouldProcess("$Method : $Namespace")) {
            # The notes name the path only; the query can hold filter values (D33).
            $NamespacePath = ($Namespace -split '\?', 2)[0]
            Write-Verbose "Starting process with method: $Method and namespace: $NamespacePath"
            # Check if session is not a SendGridSession.
            if ($script:Session -isnot [SendGridSession]) {
                throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            }
            try {
                # Invoke the query based on provided parameters.
                if ($PSBoundParameters.ContainsKey('ContentBody') -and $PSBoundParameters.ContainsKey('OnBehalfOf')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody, $OnBehalfOf)
                }
                elseif ($PSBoundParameters.ContainsKey('ContentBody')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody)
                }
                elseif ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $OnBehalfOf)
                }
                else {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace)
                }
            }
            catch {
                throw $_
            }

            # Get unique properties.
            $Properties = Get-UniqueProperties -InputObject $Query

            # Handle PSObject array with a single or more than 'Result' property.
            if ($Query -is [System.Management.Automation.PSObject[]] -and $Properties.Count -eq 1) {
                switch ($Properties) {
                    'Result' {
                        $Query = $Query.result
                        break;
                    }
                    'Results' {
                        $Query = $Query.results
                        break;
                    }
                    'Suppressions' {
                        $Query = $Query.suppressions
                        break;
                    }
                    'Messages' {
                        $Query = $Query.messages
                        $PSTypeName = 'SendGridTools.Get.SGEmailActivity'
                        break;
                    }
                    Default {
                        break;
                    }
                }
                $Properties = Get-UniqueProperties -InputObject $Query
            }
            elseif ($Query -is [System.Management.Automation.PSObject[]] -and $Properties.Count -gt 1 -and ($Properties -eq 'Result' -or $Properties -eq 'Results')) {
                switch ($Properties | Where-Object { $_ -notmatch 'Metadata' }) {
                    'Result' {
                        $Query = $Query.result
                        break;
                    }
                    'Results' {
                        $Query = $Query.results
                        break;
                    }
                    Default {
                        break;
                    }
                }
                $Properties = Get-UniqueProperties -InputObject $Query
            }

            switch ($CallingCmdlet) {
                'Get-SGAuthenticatedDomain' {
                    $PSTypeName = 'SendGridTools.Get.SGAuthenticatedDomain'
                    break
                }
                'Get-SGAuthenticatedDomain -ShowDNS' {
                    # Need a format view that is friendly to the user. Pull request requested from one happy user.
                    break
                }
                'Get-SGBrandedDomainLink -ShowDNS' {
                    # Need a format view that is friendly to the user. Pull request requested from one happy user.
                    break
                }
                'Get-SGBrandedDomainLink' {
                    $PSTypeName = 'SendGridTools.Get.SGBrandedDomainLink'
                    break
                }
                'Get-SGCombinedDomain' {
                    $PSTypeName = 'SendGridTools.Get.SGCombinedDomain'
                    break
                }
                Default {
                    break
                }
            }

            # Process each object in the query.
            foreach ($Object in $Query) {
                # Create a new custom object.
                [PSCustomObject]$PSObject = [PSCustomObject]::new()
                if ($PSTypeName) {
                    $PSObject | Add-Member -TypeName $PSTypeName
                }

                # Process each property in the properties array.
                foreach ($Property in $Properties) {
                    # Check for inline properties.
                    if ($Object.$Property -is [System.Management.Automation.PSCustomObject]) {
                        $InlineProperties = Get-UniqueProperties -InputObject $Object.$Property

                        # Process each inline property.
                        foreach ($InlineProperty in $InlineProperties) {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (('{0}{1}' -f ($Property -replace '[\s_-]+'), $($InlineProperty | ConvertTo-TitleCase) -replace '[\s_-]+')) -Value $Object.$Property.$InlineProperty
                        }
                    }

                    # An empty list gives the switch below no round, so it is kept here with its empty value (D8).
                    if (0 -eq @($Object.$Property).Count) {
                        $PSObject | Add-Member -MemberType NoteProperty -Name (($Property | ConvertTo-TitleCase) -replace '[\s_-]+') -Value $Object.$Property -Force
                        continue
                    }

                    # Unix seconds under a time name become dates in both shells; a list becomes a list of dates only when every element is a whole number (D30, D31).
                    if ($Property -match 'valid|created|updated|lastat|_at$') {
                        $TimeItems = @($Object.$Property)
                        $WholeNumbers = @($TimeItems | Where-Object { $_ -is [int] -or $_ -is [int64] })
                        if ($WholeNumbers.Count -eq $TimeItems.Count) {
                            if ($Object.$Property -is [array]) {
                                $TimeValue = [object[]]@($TimeItems | ForEach-Object { [UnixTime]::FromUnixTime($_) })
                            }
                            else {
                                $TimeValue = [UnixTime]::FromUnixTime($Object.$Property)
                            }
                            $PSObject | Add-Member -MemberType NoteProperty -Name (($Property | ConvertTo-TitleCase) -replace '[\s_-]+') -Value $TimeValue -Force
                            continue
                        }
                    }

                    # Switch based on the property type.
                    switch ($Object.$Property) {
                        { $_ -is [string] -and $Property -match '^date$' } {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (($Property | ConvertTo-TitleCase) -replace '[\s_-]+') -Value ([datetime]::Parse($_))
                            break
                        }
                        Default {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (($Property | ConvertTo-TitleCase) -replace '[\s_-]+') -Value $Object.$Property -Force
                            break
                        }
                    }
                }
                # An empty errors list is no error (D8); any other Errors value throws as before.
                if (($PSObject | Get-Member -Name 'Errors' -MemberType 'NoteProperty') -and 0 -ne @($PSObject.Errors).Count) {
                    # One entry is thrown exactly as before; with several, the messages are joined in order (D16).
                    $ErrorText = $PSObject.Errors.Message
                    $ErrorTexts = @($ErrorText | Where-Object { "$_" })
                    if (@($PSObject.Errors).Count -gt 1 -and $ErrorTexts.Count -gt 0) {
                        $ErrorText = $ErrorTexts -join '; '
                    }
                    throw $ErrorText
                }
                elseif (0 -ne @($PSObject.PSObject.Properties).Count) {
                    $PSObject
                }
            }
            Write-Verbose -Message ('Successfully invoked "{0}" on "{1}".' -f $CallingCmdlet, $NamespacePath)
        }
    }
}