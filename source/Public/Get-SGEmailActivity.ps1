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
        DefaultParameterSetName = 'Query'
    )]
    [Alias('Get-SGActivity')]
    param (
        [Parameter(
            ParameterSetName = 'Query',
            Position = 0,
            Mandatory = $true
        )]
        [Alias('Query')]
        [string]$Property,

        [Parameter(
            ParameterSetName = 'Query',
            Position = 0,
            Mandatory = $true
        )]
        [Alias('Query')]
        [string]$Value,

        [Parameter(
            ParameterSetName = 'MessageId',
            Position = 0,
            Mandatory = $true
        )]
        [string]$MessageId,

        [Parameter(
            ParameterSetName = 'Query',
            Position = 1)]
        [ValidateRange(1, 1000)]
        [int]$Limit = 10
    )
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

        if ($PSCmdlet.ParameterSetName -eq 'MessageId') {
            $InvokeSplat['Namespace'] += "/$MessageId"
        }
        else {
            #Generic List
            [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()
            $QueryParameters.Add("query=$Filter")
            $QueryParameters.Add("limit=$Limit")
            if ($QueryParameters.Count -gt 0) {
                $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
            }
        }
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid email activity. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}