Function Test-WinClatFeature {

    <#

    .SYNOPSIS
        Determines from 'netsh interface ?' output whether the WinCLAT feature is present.

    .DESCRIPTION
        Looks for 'clat' in the list that follows 'The following sub-contexts are available:' (DESIGN.md, section 4.4). The commands list earlier in the same output also mentions clat, so only the sub-context list is examined. The list may wrap over several lines and ends at the first blank line.

        Returns $false when the sub-context list is missing, for example when netsh printed an error instead.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InputObject
        The output of 'netsh.exe interface ?'. Strings that contain embedded line breaks are split into separate lines.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean. $true when the clat sub-context is present.

    .EXAMPLE
        Test-WinClatFeature -InputObject (netsh.exe interface '?')

        Returns $true on a computer that has received the WinCLAT feature.

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
    [OutputType([bool])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$InputObject

    )

    $Lines = @($InputObject | ForEach-Object -Process { $_ -split '\r?\n' })
    $InList = $false

    ForEach ($Line in $Lines) {

        If ($InList) {

            If ($Line.Trim() -eq '') {

                Break

            }

            If (($Line.Trim() -split '\s+') -contains 'clat') {

                Return $true

            }

        }

        ElseIf ($Line -match '^\s*The following sub-contexts are available:\s*$') {

            $InList = $true

        }

    }

    Return $false

}
