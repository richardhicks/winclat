Function Get-WinClatOSBuild {

    <#

    .SYNOPSIS
        Returns the operating system version including the update build revision.

    .DESCRIPTION
        Returns a string such as '10.0.26300.9711' built from CurrentMajorVersionNumber, CurrentMinorVersionNumber, CurrentBuildNumber, and UBR in the registry (DESIGN.md, section 6). [Environment]::OSVersion does not include the UBR.

        Falls back to [Environment]::OSVersion.Version when the registry values cannot be read.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER Path
        The registry key to read. The default is the Windows NT CurrentVersion key; tests supply a different key.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String.

    .EXAMPLE
        Get-WinClatOSBuild

        Returns '10.0.26300.9711' on Windows 11 build 26300 with update build revision 9711.

    .LINK
        https://learn.microsoft.com/windows/release-health/windows11-release-information

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
    [OutputType([string])]

    Param (

        [string]$Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    )

    $Key = $null

    If (Test-Path -Path $Path) {

        $Key = Get-ItemProperty -Path $Path

    }

    If ($Key -and $null -ne $Key.CurrentMajorVersionNumber -and $null -ne $Key.CurrentBuildNumber) {

        $UBR = 0

        If ($null -ne $Key.UBR) {

            $UBR = $Key.UBR

        }

        Return "$($Key.CurrentMajorVersionNumber).$($Key.CurrentMinorVersionNumber).$($Key.CurrentBuildNumber).$UBR"

    }

    Return [Environment]::OSVersion.Version.ToString()

}
