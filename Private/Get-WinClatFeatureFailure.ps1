Function Get-WinClatFeatureFailure {

    <#

    .SYNOPSIS
        Returns the status and message for a computer where the clat netsh context is missing.

    .DESCRIPTION
        Microsoft delivers WinCLAT to Windows client editions only (DESIGN.md, section 1.3). When the clat context is missing, the edition decides the result (section 4.5):
          - Windows Server, including domain controllers: Status NotSupported, because the feature will not be delivered.
          - Any other edition: Status FeatureNotAvailable, with a message naming the build where WinCLAT is generally available (Windows 11 version 25H2 build 26200.9550).

        The edition is read from ProductType in HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions: WinNT is a client, ServerNT a server, and LanmanNT a domain controller. If the value cannot be read, the computer is treated as a client.

        Call it only after the feature check has failed. A server where the clat context is present is handled like any other computer.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER OSBuild
        The OS build, for example 10.0.26100.33650, included in the message when supplied.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Status and Message properties.

    .EXAMPLE
        Get-WinClatFeatureFailure -OSBuild (Get-WinClatOSBuild)

        Returns Status NotSupported on Windows Server, and FeatureNotAvailable on a client that has not received the feature.

    .LINK
        https://learn.microsoft.com/windows/win32/api/winnt/ns-winnt-osversioninfoexa

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

        [AllowNull()]
        [AllowEmptyString()]
        [string]$OSBuild

    )

    $OnBuild = ''

    If ($OSBuild) {

        $OnBuild = " on OS build $OSBuild"

    }

    $ProductType = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name 'ProductType' -ErrorAction SilentlyContinue).ProductType

    If ($ProductType -eq 'ServerNT' -or $ProductType -eq 'LanmanNT') {

        # Status NotSupported already says the feature is missing, so the message only gives the reason (October 26, 2026).
        $Message = 'WinCLAT is not available on Windows Server.'

        If ($OSBuild) {

            $Message = "WinCLAT is not available on Windows Server (OS build $OSBuild)."

        }

        Return [PSCustomObject]@{

            Status  = 'NotSupported'
            Message = $Message

        }

    }

    [PSCustomObject]@{

        Status  = 'FeatureNotAvailable'
        Message = "The clat netsh context is not present$OnBuild. WinCLAT is generally available on Windows 11 version 25H2 build 26200.9550 and later."

    }

}
