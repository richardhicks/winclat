Function ConvertTo-WinClatIPv6Prefix {

    <#

    .SYNOPSIS
        Returns the prefix of an IPv6 address in CIDR notation.

    .DESCRIPTION
        Keeps the first PrefixLength bits of the address, clears the rest, and returns the result as a string such as '2001:579:6024:21d::/64'. Used by the CLAT address check of Test-WinClat (DESIGN.md, section 8.3), which compares the /64 of the CLAT IPv6 address with the /64 of each SLAAC address. The /64 is used rather than each address's own PrefixLength, because Windows reports temporary SLAAC addresses with a PrefixLength of 128 (section 10).

        Returns $null when the address cannot be parsed or is not IPv6.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER Address
        The IPv6 address, for example '2001:579:6024:21d:f574:f7a:4040:4260'.

    .PARAMETER PrefixLength
        The number of leading bits to keep. The default is 64.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String.

    .EXAMPLE
        ConvertTo-WinClatIPv6Prefix -Address '2001:579:6024:21d:f574:f7a:4040:4260'

        Returns '2001:579:6024:21d::/64'.

    .LINK
        https://www.rfc-editor.org/rfc/rfc4291

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

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Address,

        [ValidateRange(0, 128)]
        [int]$PrefixLength = 64

    )

    $Parsed = $null

    If (-not $Address -or -not [System.Net.IPAddress]::TryParse($Address, [ref]$Parsed) -or $Parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {

        Return $null

    }

    $Bytes = $Parsed.GetAddressBytes()

    For ($Index = 0; $Index -lt 16; $Index++) {

        $Keep = [Math]::Min([Math]::Max($PrefixLength - ($Index * 8), 0), 8)
        $Bytes[$Index] = $Bytes[$Index] -band [byte](((0xFF -shl (8 - $Keep)) -band 0xFF))

    }

    "$(New-Object -TypeName System.Net.IPAddress -ArgumentList (, $Bytes))/$PrefixLength"

}
