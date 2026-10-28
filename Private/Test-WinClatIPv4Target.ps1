Function Test-WinClatIPv4Target {

    <#

    .SYNOPSIS
        Validates the Test-WinClat -IPv4Target value.

    .DESCRIPTION
        [System.Net.IPAddress]::Parse() alone is insufficient: it accepts shortened forms ('1' parses as 0.0.0.1) and IPv6 addresses. Require all of (DESIGN.md, section 8.5):
          1. A strict dotted-quad pattern (four octets, each 0 to 255, no leading zeros).
          2. AddressFamily of InterNetwork after parsing.
          3. Not loopback (127.0.0.0/8), unspecified (0.0.0.0), broadcast (255.255.255.255), multicast (224.0.0.0/4), reserved (240.0.0.0/4), or 192.0.0.0/29.

        Leading zeros are rejected because Windows PowerShell 5.1 parses them as octal ('010' is 8) while PowerShell 7 may parse them as decimal.

        Throws a descriptive error when invalid, so ValidateScript shows a useful message. Returns $true when valid.

    .PARAMETER Address
        The IPv4 address to validate, for example '192.0.2.10'.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean. Always $true; an invalid address throws instead.

    .EXAMPLE
        Test-WinClatIPv4Target -Address '192.0.2.10'

        Returns $true.

    .EXAMPLE
        Test-WinClatIPv4Target -Address '10.1'

        Throws because the value is not a dotted-quad IPv4 address.

    .LINK
        https://learn.microsoft.com/dotnet/api/system.net.ipaddress

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
        [string]$Address

    )

    $Octet = '(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'

    If ($Address -notmatch "^$Octet(\.$Octet){3}$") {

        Throw "'$Address' is not a valid IPv4 address. Use dotted-quad notation with four octets from 0 to 255 and no leading zeros, for example 192.0.2.10."

    }

    $Parsed = $null

    If (-not [System.Net.IPAddress]::TryParse($Address, [ref]$Parsed) -or $Parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {

        Throw "'$Address' is not a valid IPv4 address."

    }

    $Bytes = $Parsed.GetAddressBytes()

    If ($Bytes[0] -eq 127) {

        Throw "'$Address' is a loopback address (127.0.0.0/8). Use an address reachable through the NAT64 gateway."

    }

    If ($Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 0 -and $Bytes[3] -eq 0) {

        Throw "'$Address' is the unspecified address. Use an address reachable through the NAT64 gateway."

    }

    If ($Bytes[0] -eq 255 -and $Bytes[1] -eq 255 -and $Bytes[2] -eq 255 -and $Bytes[3] -eq 255) {

        Throw "'$Address' is the broadcast address. Use a unicast address reachable through the NAT64 gateway."

    }

    If ($Bytes[0] -ge 224 -and $Bytes[0] -le 239) {

        Throw "'$Address' is a multicast address (224.0.0.0/4). Use a unicast address reachable through the NAT64 gateway."

    }

    If ($Bytes[0] -ge 240) {

        Throw "'$Address' is in the reserved range (240.0.0.0/4). Use a unicast address reachable through the NAT64 gateway."

    }

    If ($Bytes[0] -eq 192 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 0 -and $Bytes[3] -le 7) {

        Throw "'$Address' is in the IPv4 Service Continuity Prefix (192.0.0.0/29) used by CLAT itself. Use an address reachable through the NAT64 gateway."

    }

    Return $true

}
