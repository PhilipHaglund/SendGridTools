class UnixTime {
    [datetime]$DateTime
    [int]$UnixTimestamp

    static [datetime]EpochStart() {
        return ([datetime]::new(1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)))
    }
    
    static [datetime] FromUnixTime([int]$UnixTimestamp) {
        return [datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds($UnixTimestamp)
    }

    static [int64] FromDateTime([datetime]$DateTime) {
        return [int64]([datetime]$DateTime - ([UnixTime]::EpochStart())).TotalSeconds
    }

    UnixTime () {
        $this.DateTime = Get-Date
        $this.UnixTimestamp = $this.ToUnixTime()
    }
    UnixTime([datetime]$DateTime) {
        $this.DateTime = $DateTime
        $this.UnixTimestamp = $this.ToUnixTime()
        #$EpochStart = [datetime]::new(1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc))
        #$EpochStart = [UnixTime]::EpochStart()
        #$this.UnixTimestamp = [int]([datetime]$DateTime - $EpochStart).TotalSeconds
        
    }
    
    UnixTime([int]$UnixTimestamp) {
        $this.UnixTimestamp = $UnixTimestamp
        $this.DateTime = $this.ToDateTime()
    }

    UnixTime([string]$DateTimeString) {
        $this.DateTime = [datetime]::Parse($DateTimeString)
        $this.UnixTimestamp = $this.ToUnixTime()
    }

    [datetime] ToDateTime() {
        return [datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds($this.UnixTimestamp)
    }

    [datetime] ToDateTimeUTC() {
        return ([UnixTime]::EpochStart()).AddSeconds($this.UnixTimestamp)
    }

    [int] ToUnixTime() {
        $EpochStart = [UnixTime]::EpochStart()
        return [int]([datetime]$this.DateTime - $EpochStart).TotalSeconds
    }

    [string] ToSendGridTime() {
        return ([datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds($this.UnixTimestamp)).ToString('yyyy-MM-dd')
    }

    [string] ToString() {
        return $this.UnixTimestamp.ToString()
    }
}
class SGASM {
    [int]$GroupId
    [int[]]$GroupsToDisplay

    SGASM() {
        $this.GroupId = 0
        $this.GroupsToDisplay = @()
    }

    SGASM([int]$GroupId) {
        $this.GroupId = $GroupId
        $this.GroupsToDisplay = @()
    }
    SGASM([int]$GroupId, [int[]]$GroupsToDisplay) {
        $this.GroupId = $GroupId
        $this.GroupsToDisplay = @()
    }
    [string] ToString() {
        return $this.GroupId.ToString()
    }
}
