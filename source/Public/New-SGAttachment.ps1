function New-SGAttachment {
    <#
    .SYNOPSIS
        Creates a new SendGrid attachment object.

    .DESCRIPTION
        New-SGAttachment creates a new SendGrid attachment object based on the provided parameters.

    .PARAMETER Filename
        Specifies the filename of the attachment. Should include the file extension.

    .PARAMETER StreamData
        Specifies the stream data of the attachment. This can come from a file stream or any other IO stream source, such as a memory stream.

    .PARAMETER Path
        Specifies the path to the file for the attachment. The file at this path will be read and used as the attachment data.

    .PARAMETER Type
        Specifies the MIME type of the attachment, such as 'application/pdf' or 'image/png'. See the list here for common MIME types: https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types

    .EXAMPLE
        PS C:\> $attachment = New-SGAttachment -Filename 'document.pdf' -Path 'C:\Files\document.pdf' -Type 'application/pdf'

        This command creates a new SendGrid attachment object for the file 'document.pdf' located at 'C:\Files\document.pdf' with the MIME type 'application/pdf'.

    .EXAMPLE
        PS C:\> $fileStream = [System.IO.File]::OpenRead('C:\Files\image.png')
        PS C:\> $attachment = New-SGAttachment -Filename 'image.png' -StreamData $fileStream -Type 'image/png' 

        This command creates a new SendGrid attachment object for the file 'image.png' using a file stream with the MIME type 'image/png'.

    .EXAMPLE
        PS C:\> $memoryStream = New-Object System.IO.MemoryStream
        PS C:\> $writer = New-Object System.IO.StreamWriter($memoryStream)
        PS C:\> $writer.Write('Sample attachment content')
        PS C:\> $writer.Flush()
        PS C:\> $memoryStream.Position = 0
        PS C:\> $attachment = New-SGAttachment -Filename 'sample.txt' -StreamData $memoryStream -Type 'text/plain'

        This command creates a new SendGrid attachment object using a memory stream containing sample text content with the MIME type 'text/plain'.

    .OUTPUTS
        System.Net.Mail.Attachment
    #>
    [CmdletBinding()]
    [OutputType([System.Net.Mail.Attachment])]
    param (
        # Specifies the filename of the attachment.
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [string]$Filename,

        # Specifies the stream data of the attachment.
        [Parameter(
            Mandatory,
            Position = 1,
            ParameterSetName = 'StreamData'
        )]
        [System.IO.Stream]$StreamData,

        # Specifies the path to the file for the attachment.
        [Parameter(
            Mandatory,
            Position = 1,
            ParameterSetName = 'FilePath'
        )]
        [string]$Path,

        # Specifies the MIME type of the attachment.
        [Parameter(
            Mandatory,
            Position = 2
        )]
        [string]$Type
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'FilePath') {
            if (-Not (Test-Path -Path $Path -PathType Leaf)) {
                Throw "The file at path '$Path' does not exist."
            }
            $FileStream = [System.IO.File]::OpenRead($Path)
            $Attachment = New-Object System.Net.Mail.Attachment($FileStream, $Filename, $Type)
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'StreamData') {
            $Attachment = New-Object System.Net.Mail.Attachment($StreamData, $Filename, $Type)
        }
        else {
            Throw "Invalid parameter set."
        }

        return $Attachment
    }
    end {
        # Clean up if necessary
        if ($FileStream) {
            $FileStream.Dispose()
        }
    }
}