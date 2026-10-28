Function Get-WinClatPermitRefusal {

    <#

    .SYNOPSIS
        Returns the message for a manual instance enable refused because permit is disabled.

    .DESCRIPTION
        netsh refuses 'set instance ... state=enabled' with 'CLAT not permitted.' and exit code 1 while permit is disabled in the active store (DESIGN.md, section 10). Set-WinClatInstance checks permit before changing anything and returns this message instead, so autoenable is never disabled for an enable that cannot succeed (section 7.4).

        The remediation points at the WinCLAT policy when Group Policy controls permit, and at Set-WinClatConfiguration -Permit Enabled otherwise.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String.

    .EXAMPLE
        Get-WinClatPermitRefusal

        Returns the refusal message, with the remediation that applies to this computer.

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
    [OutputType([string])]

    Param ()

    If (@((Get-WinClatPolicyControlled) -split ',\s*') -contains 'Permit') {

        Return 'CLAT is not permitted on this computer, because Group Policy disables Permit, so an instance cannot be enabled and nothing was changed. Change the WinCLAT policy under Computer Configuration > Administrative Templates > Network > TCPIP Settings > IPv6 Transition Technologies.'

    }

    'CLAT is not permitted on this computer (Permit is disabled), so an instance cannot be enabled and nothing was changed. Run Set-WinClatConfiguration -Permit Enabled first.'

}
