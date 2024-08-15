function Get-SGEmailActivity {
    <#
    .SYNOPSIS
        Retrieves email activity from SendGrid based on the provided query.
    .DESCRIPTION
        Get-SGEmailActivity uses the SendGrid Email Activity API to filter and retrieve email activity. 
        For example, you can retrieve all bounced messages or all messages with the same subject line.
    .PARAMETER Query
        Specifies the query to filter email activity. The query must be URL encoded and use the following format: query={query_type}="{query_content}".
    .PARAMETER Limit
        Sets the number of messages to be returned. This parameter must be greater than 0 and less than or equal to 1000. If omitted, the default is 10.
    .EXAMPLE
        PS C:\> Get-SGEmailActivity -Query "to_email%3D%22example%40example.com%22" -Limit 50
        This command retrieves the email activity for the email address 'example@example.com' with a limit of 50 messages.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'PropertySet'
    )]
    [Alias('Get-SGActivity')]
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ParameterSetName = 'PropertySet'
        )]
        [Alias('Object')]
        [ValidateSet('ApiKeyId', 'ApiKeyName', 'AsmGroupId', 'AsmGroupName', 'Categories', 'Clicks', 'Events', 'FromEmail', 'LastEventTime', 'MarketingCampaignId', 'MarketingCampaignName', 'MessageId', 'OutboundIp', 'Status', 'Subject', 'Teammate', 'TemplateId', 'TemplateName', 'ToEmail')]
        [string]$Property,

        # Specifies the query to filter email activity. Use native PowerShell operators, the query will automatically be URL encoded.
        [Parameter(
            ParameterSetName = 'FilterSet',
            Position = 0,
            Mandatory
        )]
        [string]$Filter,

        # Specifies the a raw SendGrid query to filter email activity. The query will not be URL encoded. Therefor, you must provide a URL encoded query.
        [Parameter(
            ParameterSetName = 'SendGridFilterSet',
            Position = 0,
            Mandatory
        )]
        [string]$SendGridFilter,
        
        [Parameter(ParameterSetName = 'PropertySet')]
        [Parameter(ParameterSetName = 'FilterSet')]
        [Parameter(ParameterSetName = 'SendGridFilterSet')]
        [ValidateRange(1, 1000)]
        [int]$Limit = 10
    )
    DynamicParam {
        # Create a dictionary to hold the dynamic parameters
        $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        if ($null -eq $Filter -and  $null -eq $SendGridFilter) {
            if ($Property -notmatch 'LastEventTime|Events') {
                # Create the Equal parameter attribute
                $EqualParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Create the NotEqual parameter attribute
                $NotEqualParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Add the parameter attributes to an attribute collection
                $EqualAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $EqualAttributeCollection.Add($EqualParamAttribute)
                $NotEqualAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $NotEqualAttributeCollection.Add($NotEqualParamAttribute)

                # Add Alias to the parameter
                $EQAliasAttribute = [System.Management.Automation.AliasAttribute]::new('Equals')
                $NEAliasAttribute = [System.Management.Automation.AliasAttribute]::new('NotEquals')
                $EqualAttributeCollection.Add($EQAliasAttribute)
                $NotEqualAttributeCollection.Add($NEAliasAttribute)

                # Create the actual parameter(s)
                $EqualParam = [System.Management.Automation.RuntimeDefinedParameter]::new('EQ', [switch], $EqualAttributeCollection)
                $NotEqualParam = [System.Management.Automation.RuntimeDefinedParameter]::new('NE', [switch], $NotEqualAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('EQ', $EqualParam)
                $ParamDictionary.Add('NE', $NotEqualParam)
            }
            if ($Property -eq 'Clicks') {
                # Create the GreaterThan parameter attribute
                $GTParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Create the LessThan parameter attribute
                $LTParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Add the parameter attributes to an attribute collection
                $GTAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $GTAttributeCollection.Add($GTParamAttribute)
                $LTAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $LTAttributeCollection.Add($LTParamAttribute)

                # Add Alias to the parameter
                $GTAliasAttribute = [System.Management.Automation.AliasAttribute]::new('GreaterThan')
                $GTAttributeCollection.Add($GTAliasAttribute)
                $LTAliasAttribute = [System.Management.Automation.AliasAttribute]::new('LessThan')
                $LTAttributeCollection.Add($LTAliasAttribute)

                # Create the actual parameter(s)
                $GTParam = [System.Management.Automation.RuntimeDefinedParameter]::new('GT', [switch], $GTAttributeCollection)
                $LTParam = [System.Management.Automation.RuntimeDefinedParameter]::new('LT', [switch], $LTAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('GT', $GTParam)
                $ParamDictionary.Add('LT', $LTParam)
            }
            if ($Property -match 'TemplateId|TemplateName|OriginatingIp|OutboundIp|Events|MarketingCampaignName|MarketingCampaignId|Categories|AsmGroupId|AsmGroupName|Teammate') {
                # Create the Contains parameter attribute
                $ContainsParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Create the NotContains parameter attribute
                $NotContainsParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Add the parameter attributes to an attribute collection
                $ContainsAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ContainsAttributeCollection.Add($ContainsParamAttribute)
                $NotContainsAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $NotContainsAttributeCollection.Add($NotContainsParamAttribute)

                # Create the actual Contains parameter
                $ContainsParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Contains', [switch], $ContainsAttributeCollection)
                $NotContainsParam = [System.Management.Automation.RuntimeDefinedParameter]::new('NotContains', [switch], $NotContainsAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Contains', $ContainsParam)
                $ParamDictionary.Add('NotContains', $NotContainsParam)
            }
            if ($Property -match 'Subject|TemplateId|MarketingCampaignName|MarketingCampaignId|ApiKeyId|Categories|OutboundIp|Clicks|AsmGroupId|Teammate|Events') {
                # Create the IsEmpty parameter attribute
                $IsEmptyParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Create the IsNotEmpty parameter attribute
                $IsNotEmptyParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Add the parameter attributes to an attribute collection
                $IsEmptyAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $IsEmptyAttributeCollection.Add($IsEmptyParamAttribute)
                $IsNotEmptyAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $IsNotEmptyAttributeCollection.Add($IsNotEmptyParamAttribute)

                # Create the actual Contains parameter
                $IsEmptyParam = [System.Management.Automation.RuntimeDefinedParameter]::new('IsEmpty', [switch], $IsEmptyAttributeCollection)
                $IsNotEmptyParam = [System.Management.Automation.RuntimeDefinedParameter]::new('IsNotEmpty', [switch], $IsNotEmptyAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('IsEmpty', $IsEmptyParam)
                $ParamDictionary.Add('IsNotEmpty', $IsNotEmptyParam)
            }
            if ($Property -match 'MessageId|FromEmail|Subject|ToEmail|OutboundIp|OriginatingIp') {
                # Create the Like parameter attribute
                $LikeParamAttribute = [System.Management.Automation.ParameterAttribute]::new()

                # Create the IsNotEmpty parameter attribute
                $NotLikeParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                # Add the parameter attributes to an attribute collection
                $LikeAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $LikeAttributeCollection.Add($LikeParamAttribute)
                $NotLikeAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $NotLikeAttributeCollection.Add($NotLikeParamAttribute)

                # Create the actual Contains parameter
                $LikeParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Like', [switch], $LikeAttributeCollection)
                $NotLikeParam = [System.Management.Automation.RuntimeDefinedParameter]::new('NotLike', [switch], $NotLikeAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Like', $LikeParam)
                $ParamDictionary.Add('NotLike', $NotLikeParam)
            }
            #region Value Properties
            if ($Property -match 'MessageId|FromEmail|Subject|ToEmail|OutboundIp|OriginatingIp') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'Clicks') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [Int32], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'Status') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new('delivered', 'not_delivered', 'processing')
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'Events') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new('processed', 'deferred', 'delivered', 'bounce', 'open', 'click', 'dropped', 'spamreport', 'unsubscribe', 'group_unsubscribe', 'group_resubscribe')
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'TemplateId') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $script:Templates = Get-SGTemplate
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new($Templates.TemplateId)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'TemplateName') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $script:Templates = Get-SGTemplate
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$Templates.TemplateName)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'MarketingCampaignId') {
                Write-Warning -Message 'The MarketingCampaignId property is not yet implemented'
                <#
            # Create the Value parameter attribute
            $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $ValueParamAttribute.Position = 2
            $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

            # Add the parameter attributes to an attribute collection
            $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $ValueAttributeCollection.Add($ValueParamAttribute)

            # Add ValidateSet to the parameter
            $Campaigns = Get-SGCampaign
            $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new($Campaigns.CampaignId)
            $ValueAttributeCollection.Add($StatusValidateSet)

            # Create the actual Value parameter
            $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string], $ValueAttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary.Add('Value', $ValueParam)
            #>
            }

            if ($Property -eq 'MarketingCampaignName') {
                Write-Warning -Message 'The MarketingCampaignName property is not yet implemented'
                <#
            # Create the Value parameter attribute
            $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $ValueParamAttribute.Position = 2
            $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

            # Add the parameter attributes to an attribute collection
            $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $ValueAttributeCollection.Add($ValueParamAttribute)

            # Add ValidateSet to the parameter
            $Campaigns = Get-SGCampaign
            $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new($Campaigns.CampaignName)
            $ValueAttributeCollection.Add($StatusValidateSet)

            # Create the actual Value parameter
            $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string], $ValueAttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary.Add('Value', $ValueParam)
            #>
            }
            if ($Property -eq 'ApiKeyId') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $script:APIKeys = Get-SGApiKey
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$APIKeys.ApiKeyId)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'ApiKeyName') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $script:APIKeys = Get-SGApiKey
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$APIKeys.Name)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            <# NOT YET IMPLEMENTED
        if ($Property -eq 'Categories') {
            # Create the Value parameter attribute
            $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $ValueParamAttribute.Position = 2
            $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

            # Add the parameter attributes to an attribute collection
            $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $ValueAttributeCollection.Add($ValueParamAttribute)

            # Add ValidateSet to the parameter
            $script:Categories = Get-SGCategory
            $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$Categories.Category)
            $ValueAttributeCollection.Add($StatusValidateSet)

            # Create the actual Value parameter
            $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary.Add('Value', $ValueParam)
        }#>
            if ($Property -eq 'AsmGroupId') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $UnsubscribeGroups = Get-SGSuppressionGroup
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$UnsubscribeGroups.Id)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'AsmGroupName') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $script:UnsubscribeGroups = Get-SGSuppressionGroup
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$UnsubscribeGroups.Name)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            if ($Property -eq 'Teammate') {
                # Create the Value parameter attribute
                $ValueParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
                $ValueParamAttribute.Position = 2
                $ValueParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

                # Add the parameter attributes to an attribute collection
                $ValueAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
                $ValueAttributeCollection.Add($ValueParamAttribute)

                # Add ValidateSet to the parameter
                $script:Teammates = Get-SGTeammate
                $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$Teammates.Username)
                $ValueAttributeCollection.Add($StatusValidateSet)

                # Create the actual Value parameter
                $ValueParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Value', [string[]], $ValueAttributeCollection)

                # Push the parameter(s) into a parameter dictionary
                $ParamDictionary.Add('Value', $ValueParam)
            }
            #endregion Value Properties
        }
        # Return the dictionary
        return $ParamDictionary
    }
    begin {
        if ($Property -eq 'ApiKeyName') {
            $Value = ($script:APIKeys.where({ $_.Name -eq "$($PSBoundParameters['Value'])" })).ApiKeyId
            $PSBoundParameters['Value'] = $Value
        }
        if ($Property -eq 'ASMGroupName') {
            $Value = ($script:UnsubscribeGroups.where({ $_.Name -eq "$($PSBoundParameters['Value'])" })).Id
            $PSBoundParameters['Value'] = $Value
        }
        $Properties = @{
            'MessageId'             = 'msg_id'
            'FromEmail'             = 'from_email'
            'Subject'               = 'subject'
            'ToEmail'               = 'to_email'
            'Status'                = 'status'
            'TemplateId'            = 'template_id'
            'MarketingCampaignName' = 'marketing_campaign_name'
            'MarketingCampaignId'   = 'marketing_campaign_id'
            'ApiKeyId'              = 'api_key_id'
            'ApiKeyName'            = 'api_key_id'
            'Events'                = 'events'
            'Categories'            = 'categories'
            'UniqueArgs'            = 'unique_args'
            'OutboundIp'            = 'outbound_ip'
            'LastEventTime'         = 'last_event_time'
            'Clicks'                = 'clicks'
            'AsmGroupId'            = 'asm_group_id'
            'AsmGroupName'          = 'asm_group_id'
            'Teammate'              = 'teammate'
        }
        $Operators = [ordered]@{
            'EQ'          = '='
            'NE'          = '!='
            'GT'          = '>'
            'LT'          = '<'
            'IN'          = 'IN'
            'NotIn'       = 'NOT IN'
            'Like'        = 'LIKE'
            'NotLike'     = 'NOT LIKE'
            'Contains'    = 'Contains'
            'NotContains' = 'Not Contains'
            'IsEmpty'     = 'IS NULL'
            'IsNotEmpty'  = 'IS NOT NULL'
        }
    }
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'messages'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSCmdlet.ParameterSetName -eq 'FilterSet') {
            $EncodedFilter = $Filter | ConvertTo-FilterQuery
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'SendGridFilterSet') {
            $EncodedFilter = $SendGridFilter
        }
        else {
            if ($PSBoundParameters['Value'].Count -gt 1 -and $PSBoundParameters.ContainsKey('EQ')) {
                $UsedOperator = $Operators['IN']
                $ValueIsArray = $true
            }
            elseif ($PSBoundParameters['Value'].Count -gt 1 -and $PSBoundParameters.ContainsKey('NE')) {
                $UsedOperator = $Operators['NotIn']
                $ValueIsArray = $true
            }
            else {
                $ValueIsArray = $false
                foreach ($key in $Operators.Keys) {
                    if ($PSBoundParameters.ContainsKey($key)) {
                        $UsedOperator = $Operators[$key]
                        break
                    }
                }
            }

            [System.Text.StringBuilder]$FilterQuery = [System.Text.StringBuilder]::new()

            $null = $FilterQuery.Append('(')
            if ($PSBoundParameters.ContainsKey('EQ') -or $PSBoundParameters.ContainsKey('NE')) {
                $null = $FilterQuery.Append($Properties[$Property])
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append([uri]::EscapeDataString($UsedOperator))
                $null = $FilterQuery.Append(' ')
                if ($ValueIsArray) {
                    $null = $FilterQuery.Append('(')
                    foreach ($Var in ($PSBoundParameters['Value'])) {
                        $null = $FilterQuery.Append([uri]::EscapeDataString("""$Var"""))
                        $null = $FilterQuery.Append(',')
                    }
                    $null = $FilterQuery.Remove($FilterQuery.Length - 1, 1) # Remove the last comma using the length of the string and the number of characters to remove
                    $null = $FilterQuery.Append(')')
                }
                else {
                    $null = $FilterQuery.Append([uri]::EscapeDataString("""$($PSBoundParameters['Value'])"""))                
                }
            }
            elseif ($PSBoundParameters.ContainsKey('GT') -or $PSBoundParameters.ContainsKey('LT')) {
                $null = $FilterQuery.Append($Properties[$Property])
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append([uri]::EscapeDataString($UsedOperator))
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append($PSBoundParameters['Value'])
            }
            elseif ($PSBoundParameters.ContainsKey('Like') -or $PSBoundParameters.ContainsKey('NotLike')) {
                $null = $FilterQuery.Append($Properties[$Property])
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append([uri]::EscapeDataString($UsedOperator))
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append([uri]::EscapeDataString("""%$($PSBoundParameters['Value'])%"""))
            }
            elseif ($PSBoundParameters.ContainsKey('Contains') -or $PSBoundParameters.ContainsKey('NotContains')) {
                $null = $FilterQuery.Append('(')
                foreach ($Var in ($PSBoundParameters['Value'])) {
                
                    $null = $FilterQuery.Append([uri]::EscapeDataString($UsedOperator))
                    $null = $FilterQuery.Append('(')
                    $null = $FilterQuery.Append($Properties[$Property])
                    $null = $FilterQuery.Append(',')
                    $null = $FilterQuery.Append([uri]::EscapeDataString("""$Var"""))
                    $null = $FilterQuery.Append(')')
                    $null = $FilterQuery.Append(' OR ')
                }
                $null = $FilterQuery.Remove($FilterQuery.Length - 4, 4) # Remove the last ' OR ' using the length of the string and the number of characters to remove
                $null = $FilterQuery.Append(')')
            }
            elseif ($PSBoundParameters.ContainsKey('IsEmpty') -or $PSBoundParameters.ContainsKey('IsNotEmpty')) {
                $null = $FilterQuery.Append($Properties[$Property])
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append($UsedOperator)
            }
            else {
                $null = $FilterQuery.Append($Properties[$Property])
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append([uri]::EscapeDataString($UsedOperator))
                $null = $FilterQuery.Append(' ')
                $null = $FilterQuery.Append([uri]::EscapeDataString("""$($PSBoundParameters['Value'])"""))
            }

            $null = $FilterQuery.Append(')')        
            Write-Verbose -Message ("Filter Query: $($FilterQuery.ToString())")
            $EncodedFilter = $FilterQuery.ToString()
        }
        #Generic List for Query Parameters
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()
        $QueryParameters.Add("limit=$Limit")
        $QueryParameters.Add("query=$EncodedFilter")
        if ($QueryParameters.Count -gt 0) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid email activity. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
        #>
    }
}