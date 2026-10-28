Function Get-WinClatDns64Address {

    <#

    .SYNOPSIS
        Returns the AAAA addresses that DNS64 synthesizes for ipv4only.arpa on an interface.

    .DESCRIPTION
        Queries 'ipv4only.arpa' for AAAA records (RFC 7050) against the DNS servers configured on the interface, in order, and returns the addresses from the first server that answers with at least one AAAA record. When the interface has no DNS servers configured, the system resolver is used.

        Returns nothing when no AAAA record is returned, which means DNS64 is not in use or not reachable. Query failures are not reported as errors.

        Used by the prefix consistency check (DESIGN.md, section 8.3).

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InterfaceIndex
        The interface whose DNS servers are queried.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String. IPv6 addresses.

    .EXAMPLE
        Get-WinClatDns64Address -InterfaceIndex 10

        Returns '64:ff9b:1:2112::c000:aa' and '64:ff9b:1:2112::c000:ab' when the interface's DNS server performs DNS64 with that prefix.

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
    [OutputType([string])]

    Param (

        [Parameter(Mandatory)]
        [int]$InterfaceIndex

    )

    $Servers = @(Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue | ForEach-Object -Process { $_.ServerAddresses } | Where-Object -FilterScript { $_ })

    # One attempt per configured server, or a single attempt with the system resolver.
    $Attempts = @($Servers)

    If ($Attempts.Count -eq 0) {

        $Attempts = @($null)

    }

    ForEach ($Server in $Attempts) {

        # Resolve-DnsName writes the query name to the Verbose stream, which the remote script always captures (section 4.3).
        $Query = @{

            Name         = 'ipv4only.arpa'
            Type         = 'AAAA'
            DnsOnly      = $true
            QuickTimeout = $true
            ErrorAction  = 'Stop'
            Verbose      = $false

        }

        If ($Server) {

            $Query['Server'] = $Server

        }

        Try {

            $Addresses = @(Resolve-DnsName @Query | Where-Object -FilterScript { $_.Type -eq 'AAAA' -and $_.IPAddress } | ForEach-Object -Process { [string]$_.IPAddress })

        }

        Catch {

            Write-Verbose -Message "The AAAA query for ipv4only.arpa failed against server '$Server': $($_.Exception.Message)"
            Continue

        }

        If ($Addresses.Count -gt 0) {

            ForEach ($Address in $Addresses) {

                $Address

            }

            Return

        }

    }

}
