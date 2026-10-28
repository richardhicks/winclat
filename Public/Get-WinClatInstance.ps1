Function Get-WinClatInstance {

    <#

    .SYNOPSIS
        Returns per-interface Windows CLAT (WinCLAT) state.

    .DESCRIPTION
        Wraps 'netsh.exe interface clat show instance' for each up network adapter with IPv6 enabled and returns WinClat.Instance objects. Runs locally or against one or more remote computers in parallel. Requires elevation on the target computer.

        Adapters without IPv6 bound, such as a physical NIC attached to a Hyper-V virtual switch, are skipped because CLAT can never run on them. Virtual adapters with IPv6 bound, such as a Hyper-V vEthernet adapter shared with the host or a VPN adapter, are included.

        Every computer produces at least one object. Computers that cannot be reached return Status Unreachable, computers without the WinCLAT feature return FeatureNotAvailable (NotSupported on Windows Server, which Microsoft does not deliver WinCLAT to), and sessions without elevation return ElevationRequired. WinCLAT is generally available on Windows 11 version 25H2 build 26200.9550 and later. A computer with no up adapter with IPv6 enabled matching InterfaceAlias returns one Success object with no interface data and an explanatory Message, without an error.

        TriggerSource shows how an enabled instance was started, read from event 1106 in the Microsoft-Windows-IPxlatCfg/Operational log on the target: Pref64 RA, No IPv4, Manual, or Unknown (<code>) for a code not yet documented. It is empty when the instance is disabled or the event is not found, for example after the log was cleared. Mode is Manual when TriggerSource is Manual and Automatic for any other TriggerSource. Windows keeps a manually enabled instance running after AutoEnable is enabled again, so Mode can be Manual while AutoEnable is enabled. When TriggerSource is empty, Mode is Automatic when the active AutoEnable setting is enabled and Manual when it is disabled. RemotePrefixRemainingLifetimeRaw holds the netsh text only when the lifetime could not be converted to a TimeSpan, and is empty otherwise, so every object has the same columns for Export-Csv. It is left out of the list shown for a single result; use Format-List -Property * to see it. CollectedAtUtc records when netsh ran on the target, in UTC.

        The CLAT IPv6 address is regenerated each time the instance is re-created. Do not treat it as a stable identifier.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

    .PARAMETER InterfaceAlias
        Limits results to up adapters with IPv6 enabled whose name matches any of these values. Wildcards are supported.

    .PARAMETER ComputerName
        One or more computers to query. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Not used for the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections. The default is 32.

    .INPUTS
        System.String. Computer names.

        System.Management.Automation.PSObject. Objects with a DNSHostName, ComputerName, Name, or CN property, such as those from Get-ADComputer and Get-ADObject.

    .OUTPUTS
        WinClat.Instance. When a run returns exactly one result, it also carries the type name WinClat.Instance#Single, which selects a list view instead of the default table.

    .EXAMPLE
        Get-WinClatInstance

        Returns the WinCLAT state of every up adapter with IPv6 enabled on the local computer. Run from an elevated session.

    .EXAMPLE
        Get-WinClatInstance -ComputerName CLIENT4 -InterfaceAlias 'Wi-Fi'

        Returns the WinCLAT state of the Wi-Fi adapter on CLIENT4.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Get-WinClatInstance | Where-Object -FilterScript { $_.IsTranslating } | Export-Csv -Path .\translating.csv -NoTypeInformation

        Exports every interface that is actively translating across the computers in clients.txt.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Get-WinClatInstance | Where-Object -FilterScript { $_.Status -ne 'Unreachable' }

        Returns the interfaces of the computers in clients.txt that could be reached, leaving out the Unreachable rows. The warning at the end still counts the computers that were unreachable.

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

        See docs/DESIGN.md, section 7.2.

    #>

    [CmdletBinding(PositionalBinding = $false)]
    [OutputType('WinClat.Instance')]

    Param (

        [SupportsWildcards()]
        [string[]]$InterfaceAlias,
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

            ConvertTo-WinClatInstance -ComputerName $Name -Status $Status -Message $Message -CollectedAtUtc (Get-Date).ToUniversalTime()

        }

        # The alias list travels as one argument, so wrap it to stop it being spread across parameters.
        $Aliases = [string[]]@($InterfaceAlias | Where-Object -FilterScript { $_ })

        $RemoteParameters = @{

            ComputerName     = $Targets.ToArray()
            ScriptBlock      = Get-WinClatInstanceScript
            ArgumentList     = @(, $Aliases)
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

        Invoke-WinClatRemote @RemoteParameters | Measure-WinClatResult -Tally $Tally
        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'queried' -Cmdlet $PSCmdlet

    }

}
