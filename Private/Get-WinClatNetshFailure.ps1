Function Get-WinClatNetshFailure {

    <#

    .SYNOPSIS
        Classifies a failed netsh command into a WinCLAT status.

    .DESCRIPTION
        Fallback classification for a non-zero netsh exit code (DESIGN.md, section 4.4, step 4):
          - 'The following command was not found' returns FeatureNotAvailable.
          - 'The requested operation requires elevation' returns ElevationRequired.
          - Anything else returns Failed.

        The message is the non-blank output lines joined with a space, or a description of the exit code when netsh printed nothing.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InputObject
        The output of the failed netsh command.

    .PARAMETER ExitCode
        The netsh exit code.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Status and Message properties.

    .EXAMPLE
        Get-WinClatNetshFailure -InputObject $Output -ExitCode $LASTEXITCODE

        Returns Status ElevationRequired when $Output contains the netsh elevation message.

    .LINK
        https://learn.microsoft.com/windows-server/administration/windows-commands/netsh

    .NOTES
        Version:        1.0.0
        Creation Date:  October 28, 2026
        Last Updated:   October 28, 2026
        Author:         Richard Hicks
        Organization:   Richard M. Hicks Consulting, Inc.
        Contact:        rich@richardhicks.com
        Website:        https://www.richardhicks.com/

    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$InputObject,

        [Parameter(Mandatory)]
        [int]$ExitCode

    )

    $Lines = @($InputObject | ForEach-Object -Process { $_ -split '\r?\n' } | ForEach-Object -Process { $_.Trim() } | Where-Object -FilterScript { $_ -ne '' })
    $Message = $Lines -join ' '

    If ($Message -eq '') {

        $Message = "netsh.exe exited with code $ExitCode and no output."

    }

    $Status = 'Failed'

    If ($Message -match 'The following command was not found') {

        $Status = 'FeatureNotAvailable'

    }

    ElseIf ($Message -match 'The requested operation requires elevation') {

        $Status = 'ElevationRequired'

    }

    [PSCustomObject]@{

        Status  = $Status
        Message = $Message

    }

}
