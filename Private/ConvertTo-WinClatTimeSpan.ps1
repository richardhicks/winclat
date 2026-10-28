Function ConvertTo-WinClatTimeSpan {

    <#

    .SYNOPSIS
        Converts a netsh lifetime string to a TimeSpan.

    .DESCRIPTION
        Converts a lifetime value from 'netsh.exe interface clat show instance' output, such as the remote prefix remaining lifetime, to a TimeSpan.

        Observed formats: 0s, 18h34s, 17h59m29s, 18h8m3s, 18h11m51s. Components are omitted when zero.
        Pattern: '^(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$' (the day component is defensive).
        Returns $null when the value cannot be parsed, is empty, or is too large for a TimeSpan; the caller keeps the raw string.

        This function must also be available in the remote session. See DESIGN.md, sections 4.3 and 5.5.

    .PARAMETER Value
        The lifetime string to convert, for example '17h59m29s'. Leading and trailing whitespace is ignored. An empty string returns $null.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.TimeSpan, or $null when the value cannot be parsed.

    .EXAMPLE
        ConvertTo-WinClatTimeSpan -Value '17h59m29s'

        Returns a TimeSpan of 17 hours, 59 minutes, and 29 seconds.

    .EXAMPLE
        ConvertTo-WinClatTimeSpan -Value 'infinite'

        Returns $null because the value does not match the lifetime format.

    .LINK
        https://learn.microsoft.com/dotnet/api/system.timespan

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
    [OutputType([TimeSpan])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value

    )

    $Match = [regex]::Match($Value.Trim(), '^(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$')

    # Every component is optional, so an empty string matches. Require at least one component.
    If (-not $Match.Success -or $Match.Length -eq 0) {

        Return $null

    }

    $Multipliers = @(86400, 3600, 60, 1)
    [double]$TotalSeconds = 0

    For ($Index = 0; $Index -lt $Multipliers.Count; $Index++) {

        $Group = $Match.Groups[$Index + 1]

        If ($Group.Success) {

            $TotalSeconds += [double]$Group.Value * $Multipliers[$Index]

        }

    }

    # Values too large for a TimeSpan are treated as unparsable.
    Try {

        [TimeSpan]::FromSeconds($TotalSeconds)

    }

    Catch {

        $null

    }

}
