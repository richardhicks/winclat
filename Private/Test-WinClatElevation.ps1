Function Test-WinClatElevation {

    <#

    .SYNOPSIS
        Determines whether the current session is elevated.

    .DESCRIPTION
        Checks the current token with [Security.Principal.WindowsPrincipal] and IsInRole(Administrator) (DESIGN.md, section 4.4, step 2). The token is checked rather than netsh output because a missing feature and an elevation failure both return netsh exit code 1.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean. $true when the session is elevated.

    .EXAMPLE
        Test-WinClatElevation

        Returns $false in a PowerShell session that was not started with Run as administrator.

    .LINK
        https://learn.microsoft.com/dotnet/api/system.security.principal.windowsprincipal.isinrole

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

    Param ()

    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal -ArgumentList $Identity

    Return $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

}
