Function Get-WinClatPolicyControlled {

    <#

    .SYNOPSIS
        Returns the WinCLAT settings that Group Policy controls on this computer.

    .DESCRIPTION
        Reads the WinCLAT policy registry key (DESIGN.md, section 9) and returns the controlled settings as a comma-separated string of property names in a fixed order: Permit, Pref64FromDns, Pref64FromRA. A setting is controlled when its policy value exists, whether it is 1 or 0.

        Returns an empty string when no WinCLAT policy applies. There is no policy for autoenable.

        A string keeps the output flat for Export-Csv. See DESIGN.md, section 6.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER Path
        The policy registry key to read. The default is the WinCLAT policy key; tests supply a different key.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String.

    .EXAMPLE
        Get-WinClatPolicyControlled

        Returns 'Permit, Pref64FromRA' when policy sets PermitNonCellularCLAT and GetPrefixInfoFromRA.

    .LINK
        https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-tcpip

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

        [string]$Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition\IPxlatCfgSvc'

    )

    If (-not (Test-Path -Path $Path)) {

        Return ''

    }

    $Key = Get-ItemProperty -Path $Path

    # Property name and policy registry value, in output order.
    $Policies = [ordered]@{

        'Permit'        = 'PermitNonCellularCLAT'
        'Pref64FromDns' = 'GetPrefixInfoFromDNS'
        'Pref64FromRA'  = 'GetPrefixInfoFromRA'

    }

    $Controlled = ForEach ($Name in $Policies.Keys) {

        If ($Key -and $Key.PSObject.Properties[$Policies[$Name]]) {

            $Name

        }

    }

    Return (@($Controlled) -join ', ')

}
