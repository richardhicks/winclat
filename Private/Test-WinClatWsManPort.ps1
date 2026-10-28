Function Test-WinClatWsManPort {

    <#

    .SYNOPSIS
        Checks which computers answer on the WinRM HTTP port before Invoke-Command is used.

    .DESCRIPTION
        Starts one TCP connection to the WinRM port of every computer at the same time with System.Net.Sockets.TcpClient and waits up to the timeout for all of them (DESIGN.md, section 4.3). A computer that does not accept the connection in time is reported, so Invoke-WinClatRemote can return it as Unreachable at once instead of waiting for a WinRM connection timeout. Ping is not used, because ICMP is often blocked where WinRM is allowed.

        Returns a hashtable of the computers that failed, keyed by name, with a short message as the value:
          - The name cannot be resolved in DNS.
          - The connection was refused, so the computer is up but WinRM is not listening.
          - No answer within the timeout: the computer may be offline, WinRM may not be enabled, or a firewall may drop the connection. Windows retries a refused connection for about two seconds, so a computer with WinRM off usually ends here rather than as refused.
        Computers that answered are not in the hashtable. A computer that answers can still fail later in WinRM, for example on authentication; Invoke-WinClatRemote reports that as before.

        Failures are read from the task state rather than caught as exceptions, because an exception caught inside an advanced function is also added to the caller's -ErrorVariable.

    .PARAMETER ComputerName
        The remote computers to check.

    .PARAMETER Port
        The TCP port. The default is 5985, the WinRM HTTP port.

    .PARAMETER TimeoutMilliseconds
        How long to wait for all connections. The default is 2000.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable.

    .EXAMPLE
        Test-WinClatWsManPort -ComputerName 'CLIENT4', 'CLIENT9'

        Returns @{ CLIENT9 = 'WinRM (TCP 5985) did not respond within 2 seconds. ...' } when CLIENT9 is offline.

    .LINK
        https://learn.microsoft.com/dotnet/api/system.net.sockets.tcpclient.connectasync

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
    [OutputType([hashtable])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ComputerName,

        [ValidateRange(1, 65535)]
        [int]$Port = 5985,

        [ValidateRange(1, 600000)]
        [int]$TimeoutMilliseconds = 2000

    )

    $Failed = @{}
    $Attempts = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $Seconds = [Math]::Round($TimeoutMilliseconds / 1000, 1)

    ForEach ($Name in $ComputerName) {

        $Client = New-Object -TypeName System.Net.Sockets.TcpClient -ArgumentList ([System.Net.Sockets.AddressFamily]::InterNetworkV6)

        # Accept both IPv4 and IPv6 addresses for the name.
        $Client.Client.DualMode = $true
        $Attempts.Add([PSCustomObject]@{ Name = $Name; Client = $Client; Task = $Client.ConnectAsync($Name, $Port) })

    }

    # Poll instead of Task.WaitAll, which throws when any connection fails.
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()

    While ($Watch.ElapsedMilliseconds -lt $TimeoutMilliseconds -and @($Attempts | Where-Object -FilterScript { -not $_.Task.IsCompleted }).Count -gt 0) {

        Start-Sleep -Milliseconds 25

    }

    ForEach ($Attempt in $Attempts) {

        $Task = $Attempt.Task

        If (-not $Task.IsCompleted) {

            # Windows retries a refused connection for about two seconds, so WinRM not listening usually ends here too.
            $Failed[$Attempt.Name] = "WinRM (TCP $Port) did not respond within $Seconds seconds. The computer may be offline, remote management may not be enabled, or a firewall may block it."

        }

        ElseIf ($Task.IsFaulted -or $Task.IsCanceled -or -not $Attempt.Client.Connected) {

            $Code = $null

            If ($Task.Exception) {

                $Inner = $Task.Exception.GetBaseException()

                If ($Inner -is [System.Net.Sockets.SocketException]) {

                    $Code = $Inner.SocketErrorCode

                }

            }

            $Message = "WinRM (TCP $Port) could not be reached ($Code). The computer may be offline, or remote management is not enabled."

            If ($Code -eq [System.Net.Sockets.SocketError]::HostNotFound -or $Code -eq [System.Net.Sockets.SocketError]::NoData -or $Code -eq [System.Net.Sockets.SocketError]::TryAgain) {

                $Message = 'The name cannot be resolved in DNS, so the computer was not contacted.'

            }

            ElseIf ($Code -eq [System.Net.Sockets.SocketError]::ConnectionRefused) {

                $Message = "The computer refused a connection on TCP $Port, so WinRM is not listening. Remote management is not enabled."

            }

            ElseIf (-not $Code) {

                $Message = "WinRM (TCP $Port) could not be reached. The computer may be offline, or remote management is not enabled."

            }

            $Failed[$Attempt.Name] = $Message

        }

        # Closing a pending connection ends it; a faulted task's exception is observed above, or ignored by the runtime.
        $Attempt.Client.Close()

    }

    $Failed

}
