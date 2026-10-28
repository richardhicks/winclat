Function Test-WinClatTcp {

    <#

    .SYNOPSIS
        Runs the TCP functional test against an IPv4 target and port.

    .DESCRIPTION
        Opens one TCP connection with System.Net.Sockets.TcpClient constructed with AddressFamily.InterNetwork, which guarantees an IPv4 socket, with a three-second connect timeout (DESIGN.md, section 8.4):
          - Connected returns Pass.
          - Connection refused returns Pass, because a translated reset proves the CLAT path.
          - No response within the timeout returns Warning; the target may be unreachable or filtered.
          - Any other socket error returns Fail, because it means there is no working IPv4 path.

        Returns an object with Result and Detail. Detail records the method, target, and port.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER Target
        The IPv4 address to test. Validated by Test-WinClatIPv4Target before it reaches this function.

    .PARAMETER Port
        The TCP port to connect to.

    .PARAMETER TimeoutMilliseconds
        The connect timeout. The default is 3000.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Result and Detail properties.

    .EXAMPLE
        Test-WinClatTcp -Target '192.0.2.10' -Port 443

        Returns Result Pass when a connection to 192.0.2.10 port 443 succeeds or is refused.

    .LINK
        https://learn.microsoft.com/dotnet/api/system.net.sockets.tcpclient

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

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000

    )

    $Client = New-Object -TypeName System.Net.Sockets.TcpClient -ArgumentList ([System.Net.Sockets.AddressFamily]::InterNetwork)

    Try {

        $Task = $Client.ConnectAsync($Target, $Port)

        If ($Task.Wait($TimeoutMilliseconds)) {

            Return [PSCustomObject]@{ Result = 'Pass'; Detail = "TCP connection to $Target port ${Port}: connected." }

        }

        [PSCustomObject]@{ Result = 'Warning'; Detail = "TCP connection to $Target port ${Port}: no response within $TimeoutMilliseconds ms. The target may be unreachable or filtered." }

    }

    Catch {

        # Find the socket error inside the method invocation and aggregate exceptions.
        $Exception = $_.Exception

        While ($Exception -and $Exception -isnot [System.Net.Sockets.SocketException]) {

            $Exception = $Exception.InnerException

        }

        If ($Exception -and $Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionRefused) {

            Return [PSCustomObject]@{ Result = 'Pass'; Detail = "TCP connection to $Target port ${Port}: connection refused. A translated reset proves the CLAT path." }

        }

        $Message = $_.Exception.Message

        If ($Exception) {

            $Message = "$($Exception.SocketErrorCode): $($Exception.Message)"

        }

        [PSCustomObject]@{ Result = 'Fail'; Detail = "TCP connection to $Target port ${Port}: $Message There is no working IPv4 path." }

    }

    Finally {

        $Client.Close()

    }

}
