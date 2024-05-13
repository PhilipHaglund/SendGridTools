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
        DefaultParameterSetName = 'Default'
    )]
    [Alias('Get-SGActivity')]
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [Alias('Query')]
        [ValidateSet('ApiKeyId', 'AsmGroupId', 'Categories', 'Clicks', 'Events', 'FromEmail', 'LastEventTime', 'MarketingCampaignId', 'MarketingCampaignName', 'MessageId', 'OutboundIp', 'Status', 'Subject', 'Teammate', 'TemplateId', 'ToEmail', 'UniqueArgs')]
        [string]$Property,

        [Parameter(
            Position = 2,
            Mandatory = $true
        )]
        [string]$Value,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Limit = 10
    )
    DynamicParam {
        # Create a dictionary to hold the dynamic parameters
        $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

        if ($Property -ne 'LastEventTime') {
            # Create the Equal parameter attribute
            $EqualParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $EqualParamAttribute.Position = 1
            $EqualParamAttribute.ParameterSetName = 'EqualSet'

            # Create the NotEqual parameter attribute
            $NotEqualParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $NotEqualParamAttribute.Position = 1
            $NotEqualParamAttribute.ParameterSetName = 'NotEqualSet'

            # Add the parameter attributes to an attribute collection
            $EqualAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $EqualAttributeCollection.Add($EqualParamAttribute)
            $NotEqualAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $NotEqualAttributeCollection.Add($NotEqualAttributeCollection)

            # Add Alias to the parameter
            $EQAliasAttribute = [System.Management.Automation.AliasAttribute]::new('Equals')
            $NEAliasAttribute = [System.Management.Automation.AliasAttribute]::new('Equals')
            $EqualAttributeCollection.Add($EQAliasAttribute)
            $NotEqualAttributeCollection.Add($NEAliasAttribute)

            # Create the actual EQ parameter
            $EqualParam = [System.Management.Automation.RuntimeDefinedParameter]::new('EQ', [switch], $AttributeCollection)
            $NotEqualParam = [System.Management.Automation.RuntimeDefinedParameter]::new('NE', [switch], $NotEqualAttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary.Add('EQ', $EqualParam)
            $ParamDictionary.Add('NE', $NotEqualParam)
        }
        if ($Property -eq 'LastEventTime') {
            # Create the Date parameter attribute
            $DateParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $DateParamAttribute.Position = 1
            $DateParamAttribute.ParameterSetName = 'DateSet'

            # Add the parameter attributes to an attribute collection
            $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $AttributeCollection.Add($DateParamAttribute)

            # Create the actual GT parameter
            $DateParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Date', [switch], $AttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary.Add('Date', $DateParam)
        }
        if ($Property -match 'Clicks|')
        # Return the dictionary
        return $ParamDictionary
    }
    begin {
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
            'Events'                = 'events'
            'Categories'            = 'categories'
            'UniqueArgs'            = 'unique_args'
            'OutboundIp'            = 'outbound_ip'
            'LastEventTime'         = 'last_event_time'
            'Clicks'                = 'clicks'
            'AsmGroupId'            = 'asm_group_id'
            'Teammate'              = 'teammate'
        }
    }
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'v3/messages'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

            #Generic List for Query Parameters
            [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()
            $QueryParameters.Add("query=$Filter")
            $QueryParameters.Add("limit=$Limit")
            if ($QueryParameters.Count -gt 0) {
                $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
            }
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid email activity. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}