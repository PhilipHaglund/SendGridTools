class UnixTime {
    [datetime]$DateTime
    [int]$UnixTimestamp

    static [datetime]EpochStart() {
        return ([datetime]::new(1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)))
    }

    
    UnixTime () {

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

    [datetime] ToDateTime() {
        return [datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds($this.UnixTimestamp)
    }

    [datetime] ToDateTimeUTC() {
        return [datetime]::new(1970, 1, 1, 0, 0, 0, 0, [DateTimeKind]::Utc).AddSeconds($this.UnixTimestamp)
    }

    [UnixTime] ToUnixTime() {
        $EpochStart = [UnixTime]::EpochStart()
        Write-Verbose $EpochStart -Verbose
        Write-Verbose ([int]([datetime]$this.DateTime - $EpochStart).TotalSeconds) -Verbose
        return [int]([datetime]$this.DateTime - $EpochStart).TotalSeconds
    }

    [string] ToString() {
        return $this.UnixTimestamp.ToString()
    }
}