Function Test-WinClatIcmp {

    <#

    .SYNOPSIS
        Runs the ICMP functional test against an IPv4 target.

    .DESCRIPTION
        Sends up to three ICMP echo requests with System.Net.NetworkInformation.Ping, each with a two-second timeout (DESIGN.md, section 8.4):
          - An echo reply returns Pass.
          - A destination unreachable response returns Pass, because a translated reply proves the CLAT path.
          - No response to any attempt returns Warning; the target may be unreachable or filtered.
          - Any other status, or an exception, returns Fail, because it means there is no working IPv4 path.

        Returns an object with Result and Detail. Detail records the method and target.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER Target
        The IPv4 address to test. Validated by Test-WinClatIPv4Target before it reaches this function.

    .PARAMETER Attempts
        The maximum number of echo requests. The default is 3.

    .PARAMETER TimeoutMilliseconds
        The timeout for each echo request. The default is 2000.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Result and Detail properties.

    .EXAMPLE
        Test-WinClatIcmp -Target '192.0.2.10'

        Returns Result Pass when 192.0.2.10 answers an echo request.

    .LINK
        https://learn.microsoft.com/dotnet/api/system.net.networkinformation.ping

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

        [Parameter(Mandatory)]
        [string]$Target,

        [ValidateRange(1, 10)]
        [int]$Attempts = 3,

        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 2000

    )

    $Unreachable = @('DestinationUnreachable', 'DestinationHostUnreachable', 'DestinationNetworkUnreachable', 'DestinationPortUnreachable', 'DestinationProtocolUnreachable', 'DestinationProhibited')
    $Ping = New-Object -TypeName System.Net.NetworkInformation.Ping

    Try {

        For ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {

            Try {

                $Reply = $Ping.Send($Target, $TimeoutMilliseconds)

            }

            Catch {

                $Message = $_.Exception.Message

                If ($_.Exception.InnerException) {

                    $Message = $_.Exception.InnerException.Message

                }

                Return [PSCustomObject]@{ Result = 'Fail'; Detail = "ICMP echo to ${Target}: the request failed ($Message). There is no working IPv4 path." }

            }

            $Status = [string]$Reply.Status

            If ($Status -eq 'Success') {

                Return [PSCustomObject]@{ Result = 'Pass'; Detail = "ICMP echo to ${Target}: reply in $($Reply.RoundtripTime) ms (attempt $Attempt of $Attempts)." }

            }

            If ($Unreachable -contains $Status) {

                Return [PSCustomObject]@{ Result = 'Pass'; Detail = "ICMP echo to ${Target}: $Status returned. A translated reply proves the CLAT path." }

            }

            If ($Status -ne 'TimedOut') {

                Return [PSCustomObject]@{ Result = 'Fail'; Detail = "ICMP echo to ${Target}: $Status. There is no working IPv4 path." }

            }

        }

        [PSCustomObject]@{ Result = 'Warning'; Detail = "ICMP echo to ${Target}: no reply after $Attempts attempts of $TimeoutMilliseconds ms. The target may be unreachable or filtered." }

    }

    Finally {

        $Ping.Dispose()

    }

}
