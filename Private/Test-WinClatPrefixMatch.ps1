Function Test-WinClatPrefixMatch {

    <#

    .SYNOPSIS
        Determines whether an IPv6 address falls within a /96 NAT64 prefix.

    .DESCRIPTION
        Compares the first 96 bits of the address with the prefix (DESIGN.md, section 8.3, prefix consistency). Used to check that the AAAA record DNS64 synthesizes for ipv4only.arpa uses the same prefix as the CLAT instance's remote prefix.

        Returns $false when either value cannot be parsed or the prefix is not a /96.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER Prefix
        The NAT64 prefix in CIDR notation, for example '64:ff9b:1:2112::/96'.

    .PARAMETER Address
        The IPv6 address to compare, for example '64:ff9b:1:2112::c000:aa'.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean.

    .EXAMPLE
        Test-WinClatPrefixMatch -Prefix '64:ff9b::/96' -Address '64:ff9b::c000:aa'

        Returns $true.

    .LINK
        https://www.rfc-editor.org/rfc/rfc7050

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
        [string]$Prefix,

        [Parameter(Mandatory)]
        [string]$Address

    )

    $Parts = $Prefix -split '/'

    If ($Parts.Count -ne 2 -or $Parts[1] -ne '96') {

        Return $false

    }

    $PrefixAddress = $null
    $CandidateAddress = $null

    If (-not [System.Net.IPAddress]::TryParse($Parts[0], [ref]$PrefixAddress) -or -not [System.Net.IPAddress]::TryParse($Address, [ref]$CandidateAddress)) {

        Return $false

    }

    If ($PrefixAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6 -or $CandidateAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {

        Return $false

    }

    $PrefixBytes = $PrefixAddress.GetAddressBytes()
    $CandidateBytes = $CandidateAddress.GetAddressBytes()

    For ($Index = 0; $Index -lt 12; $Index++) {

        If ($PrefixBytes[$Index] -ne $CandidateBytes[$Index]) {

            Return $false

        }

    }

    Return $true

}
