Function Test-WinClat {

    <#

    .SYNOPSIS
        Diagnoses Windows CLAT (WinCLAT) readiness and operation.

    .DESCRIPTION
        Runs global and per-interface health checks and returns one WinClat.TestSummary object per computer: the overall result (Pass, Warning, Fail, or NotApplicable), the number of passed, warning, and failed checks, whether any interface is translating, and Issues, which names each check that failed or warned, with its interface. Runs locally or against one or more remote computers in parallel.

        When Overall is Fail or Warning, run Test-WinClat -ComputerName <name> -Detailed | Format-List for the computers concerned to see the result of every check, with a Detail explaining what was found and a Remediation for each warning and failure. The default table for -Detailed shows the Detail but not the Remediation, so pipe it to Format-List to see both. -Detailed returns one flat WinClat.TestResult object per check, with Result Pass, Warning, Fail, Info, or Skipped.

        Global checks do not require elevation: Feature present, CLAT permitted, Prefix discovery valid, Policy override, and Policy controlled (only when Group Policy controls a WinCLAT setting). When Permit is disabled, as it is by default in Windows, CLAT permitted fails only when an interface is IPv6-only and could use CLAT, and is Info otherwise, so an untouched configuration on a dual-stack network does not fail. Without elevation the interfaces are not read and the check is Info. In an elevated session where a manually enabled instance is still translating, the check is a Warning that says how to stop CLAT or keep it, because disabling Permit stops automatically enabled instances but not manually enabled ones. WinCLAT is generally available on Windows 11 version 25H2 build 26200.9550 and later; on an earlier build Feature present fails and its Remediation names that build. On Windows Server, which Microsoft does not deliver WinCLAT to, Feature present is Info instead of Fail, every row has Status NotSupported, and the summary Overall is NotApplicable.

        Interface checks require elevation and run for each up adapter with IPv6 enabled: SLAAC address, IPv6 default route, Native IPv4, Instance active, CLAT address, and Prefix consistency, followed by one computer-wide Mode sanity check. CLAT address fails when the CLAT IPv6 address is not assigned to the adapter or not on its current prefix, which happens after a network change because CLAT keeps its address on the previous prefix (a known issue that Microsoft has acknowledged). IPv4 through CLAT then fails although Instance active passes; restarting the network adapter fixes it. When the session is not elevated, each interface check returns one Skipped row instead of failing the computer. Adapters that are not connected to an IPv6 network, such as the Hyper-V Default Switch or a VPN adapter, report Info rather than Fail.

        When IPv4Target is supplied and an interface is translating, a functional test follows: up to three ICMP echo requests, or one TCP connection when IPv4Port is also supplied. A reply, connection, destination unreachable, or connection refused all prove the CLAT path and return Pass. Use an IPv4 address, not a name: a name can be reached through DNS64 and NAT64 without CLAT.

        Status is the computer-level status: Success when the checks ran, even if some failed, and Unreachable or Failed when they could not run. An unreachable computer reports Overall Fail with Issues 'Connectivity', and with -Detailed one 'Connectivity' row with Result Fail. Neither failed checks nor computers that could not be tested write errors; their rows carry the outcome, and in a run for several computers one warning at the end counts the computers that could not be tested.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

    .PARAMETER InterfaceAlias
        Limits interface checks to up adapters with IPv6 enabled whose name matches any of these values. Wildcards are supported. Mode sanity always considers every adapter.

    .PARAMETER IPv4Target
        IPv4 address used for the functional test. The alias -Target can be used instead. Choose a target known to respond, ideally your own infrastructure. Loopback, unspecified, broadcast, multicast, reserved, and 192.0.0.0/29 addresses are rejected. The test is not bound to an interface: Windows sends it through the IPv4 route it prefers, and the Detail names the interface and source address it used. Windows prefers a native IPv4 route over CLAT, so on a computer with native IPv4 on another interface the test does not reach CLAT, and its Result is Info, not Pass. When several interfaces are translating, it shows that IPv4 works through CLAT on one of them, not on each.

    .PARAMETER IPv4Port
        TCP port for the functional test. When omitted, ICMP echo is used. The alias -Port can be used instead.

    .PARAMETER Detailed
        Returns one WinClat.TestResult object per check, with its Result, Detail, and Remediation, instead of one WinClat.TestSummary object per computer. The default table shows the Detail; use Format-List to see the Remediation as well.

    .PARAMETER ComputerName
        One or more computers to test. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Not used for the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections. The default is 32.

    .INPUTS
        System.String. Computer names.

        System.Management.Automation.PSObject. Objects with a DNSHostName, ComputerName, Name, or CN property, such as those from Get-ADComputer and Get-ADObject.

    .OUTPUTS
        WinClat.TestSummary, or WinClat.TestResult with -Detailed. When a run returns exactly one result, such as the summary for one computer, it also carries the type name <type>#Single, which selects a list view instead of the default table.

    .EXAMPLE
        Test-WinClat

        Runs every check on the local computer and returns its summary. Run from an elevated session to include the interface checks.

    .EXAMPLE
        Test-WinClat -Detailed

        Runs every check on the local computer and returns one row per check, with the result and detail of each in a table.

    .EXAMPLE
        Test-WinClat -ComputerName CLIENT6 -Detailed | Where-Object -FilterScript { $_.Result -in 'Warning', 'Fail' } | Format-List -Property Check, InterfaceAlias, Detail, Remediation

        Shows only the checks that warned or failed on CLIENT6, with what was found and how to fix it.

    .EXAMPLE
        Test-WinClat -ComputerName CLIENT4 -IPv4Target 192.0.2.10 -IPv4Port 443

        Runs every check on CLIENT4, then tests a TCP connection to 192.0.2.10 port 443 through CLAT, and returns the summary.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Test-WinClat | Where-Object -FilterScript { $_.Overall -in 'Warning', 'Fail' } | Format-Table -Property ComputerName, Overall, Issues

        Lists the computers in clients.txt that have a warning or failure, and which checks they are.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Test-WinClat -Detailed | Where-Object -FilterScript { $_.Result -in 'Warning', 'Fail' } | Export-Csv -Path .\winclat-issues.csv -NoTypeInformation

        Exports every warning and failure across the computers in clients.txt, with the detail and remediation of each, one row per check.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Test-WinClat | Export-Csv -Path .\winclat-health.csv -NoTypeInformation

        Exports one summary row per computer.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Test-WinClat | Where-Object -FilterScript { $_.Status -ne 'Unreachable' }

        Returns the summaries of the computers in clients.txt that could be reached, leaving out the Unreachable rows. The warning at the end still counts the computers that were unreachable.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Test-WinClat | Where-Object -FilterScript { $_.Status -eq 'Unreachable' } | Select-Object -ExpandProperty ComputerName | Set-Content -Path .\retry.txt

        Saves the names of the computers in clients.txt that could not be reached to retry.txt, so they can be tested again later with Get-Content -Path .\retry.txt | Test-WinClat.

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

        See docs/DESIGN.md, section 8.

    #>

    [CmdletBinding(PositionalBinding = $false)]
    [OutputType('WinClat.TestSummary', 'WinClat.TestResult')]

    Param (

        [SupportsWildcards()]
        [string[]]$InterfaceAlias,

        [ValidateScript({ Test-WinClatIPv4Target -Address $_ })]
        [Alias('Target')]
        [string]$IPv4Target,

        [ValidateRange(1, 65535)]
        [Alias('Port')]
        [int]$IPv4Port,

        [switch]$Detailed,

        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DNSHostName', 'CN', 'Name')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [PSCredential]$Credential,

        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit = 32

    )

    Begin {

        $Targets = New-Object -TypeName 'System.Collections.Generic.List[string]'

    }

    Process {

        # Read $_ only for pipeline input; otherwise it may be an outer ForEach-Object variable.
        $PipelineObject = $null

        If ($MyInvocation.ExpectingInput) {

            $PipelineObject = $_

        }

        ForEach ($Name in @(Get-WinClatTargetName -InputObject $PipelineObject -ComputerName $ComputerName -Cmdlet $PSCmdlet)) {

            $Targets.Add($Name)

        }

    }

    End {

        $NewFailure = {

            Param ($Name, $Status, $Message)

            $Row = @{

                ComputerName   = $Name
                Status         = $Status
                Check          = 'Test run'
                Result         = 'Fail'
                Detail         = $Message
                CollectedAtUtc = (Get-Date).ToUniversalTime()

            }

            If ($Status -eq 'Unreachable') {

                $Row['Check'] = 'Connectivity'
                $Row['Remediation'] = 'Confirm that the computer is online, WinRM is enabled, and the credentials are valid.'

            }

            ConvertTo-WinClatTestResult @Row

        }

        # The alias list travels as one argument, so the array literal keeps it as the first element.
        $Aliases = [string[]]@($InterfaceAlias | Where-Object -FilterScript { $_ })

        $RemoteParameters = @{

            ComputerName     = $Targets.ToArray()
            ScriptBlock      = Get-WinClatTestScript
            ArgumentList     = @($Aliases, $IPv4Target, $IPv4Port)
            ThrottleLimit    = $ThrottleLimit
            NewFailureObject = $NewFailure
            Cmdlet           = $PSCmdlet

        }

        If ($Credential) {

            $RemoteParameters['Credential'] = $Credential

        }

        # One summary warning at the end instead of an error per computer (DESIGN.md, section 4.6). For a single computer the
        # results are held, so exactly one is shown as a list and several as a table (section 6); fleet results still stream.
        $Tally = New-WinClatTally -ComputerName $Targets.ToArray()

        # The checks are the same either way; -Detailed only changes what is returned (DESIGN.md, section 8.6).
        If ($Detailed) {

            Invoke-WinClatRemote @RemoteParameters | Measure-WinClatResult -Tally $Tally
            Complete-WinClatResult -Tally $Tally
            Write-WinClatFailureSummary -Tally $Tally -Action 'queried' -Cmdlet $PSCmdlet
            Return

        }

        # Group the rows by computer, keeping the order in which computers first appear.
        $Groups = [ordered]@{}

        ForEach ($Row in @(Invoke-WinClatRemote @RemoteParameters | Measure-WinClatResult -Tally $Tally -NoHold)) {

            $Key = [string]$Row.ComputerName

            If (-not $Groups.Contains($Key)) {

                $Groups[$Key] = New-Object -TypeName 'System.Collections.Generic.List[object]'

            }

            $Groups[$Key].Add($Row)

        }

        ForEach ($Key in $Groups.Keys) {

            ConvertTo-WinClatTestSummary -ComputerName $Key -InputObject $Groups[$Key].ToArray() | Measure-WinClatResult -Tally $Tally

        }

        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'queried' -Cmdlet $PSCmdlet

    }

}
