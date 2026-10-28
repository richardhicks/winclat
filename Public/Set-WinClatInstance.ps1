Function Set-WinClatInstance {

    <#

    .SYNOPSIS
        Manually enables or disables Windows CLAT (WinCLAT) on an interface.

    .DESCRIPTION
        Wraps 'netsh.exe interface clat set instance'. Runs locally or against one or more remote computers in parallel, and returns WinClat.SetResult objects. Requires elevation on the target computer. Every change asks for confirmation unless -Confirm:$false is supplied.

        netsh refuses 'set instance' while AutoEnable is enabled, so:
          - -State Enabled on a computer in automatic mode disables AutoEnable first and then enables the instance, under one confirmation. Disabling AutoEnable stops CLAT on every interface where it was automatically enabled. The result includes an AutoEnable row as well as the State row.
          - -State Disabled on a computer in automatic mode is refused with Status Failed, and nothing is changed. To stop CLAT in automatic mode, run Set-WinClatConfiguration -AutoEnable Disabled, which affects every automatically enabled interface.

        netsh also refuses a manual enable while Permit is disabled, so -State Enabled on such a computer is refused with Status Failed before anything is changed, and AutoEnable is not disabled. Run Set-WinClatConfiguration -Permit Enabled first, or change the WinCLAT policy when Group Policy disables Permit.

        A manually enabled instance keeps running when AutoEnable is enabled again, and also when AutoEnable or Permit is disabled later, because disabling either one stops only automatically enabled instances. To stop it, disable AutoEnable and then run Set-WinClatInstance -State Disabled. Get-WinClatInstance reports such an instance with Mode Manual and TriggerSource Manual.

        The interface is selected by exact name or by interface index. Computers where the adapter is missing, not up, or has IPv6 unbound are refused, because CLAT can never run there.

        IMPORTANT: Manual instance state is runtime only. It survives an adapter restart and link loss but is lost on reboot, while AutoEnable remains disabled. After a reboot, CLAT is permitted but never activates until AutoEnable is re-enabled with Set-WinClatConfiguration -AutoEnable Enabled, or the instance is enabled again. A warning is written after every manual enable.

        set instance prints nothing on success, so the instance is read back after the change. After a manual enable, translation can take several seconds to start; use Get-WinClatInstance to check.

        The function does not write a log. Each result object records what was requested and what was read back, so piping the results to Export-Csv keeps a complete record of a run (see the examples). PowerShell script block logging or transcription enabled by policy also records each call. On each target, Windows logs every instance enable and disable, with its trigger source (Manual or automatic), in the Microsoft-Windows-IPxlatCfg/Operational event log.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

    .PARAMETER InterfaceAlias
        The exact name of the adapter to change, for example 'Ethernet'. Wildcards are not supported.

    .PARAMETER InterfaceIndex
        The interface index of the adapter to change. Interface indexes differ between computers, so this is mainly useful for a single computer.

    .PARAMETER State
        Enabled or Disabled.

    .PARAMETER ComputerName
        One or more computers to change. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Not used for the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections. The default is 32.

    .INPUTS
        System.String. Computer names.

        System.Management.Automation.PSObject. Objects with a DNSHostName, ComputerName, Name, or CN property, such as those from Get-ADComputer and Get-ADObject.

    .OUTPUTS
        WinClat.SetResult. When a run returns exactly one result, it also carries the type name WinClat.SetResult#Single, which selects a list view instead of the default table.

    .EXAMPLE
        Set-WinClatInstance -InterfaceAlias 'Ethernet' -State Enabled

        Enables CLAT manually on the Ethernet adapter of the local computer, after confirmation. If AutoEnable is enabled, it is disabled first.

    .EXAMPLE
        Set-WinClatInstance -ComputerName CLIENT4 -InterfaceIndex 6 -State Disabled -Confirm:$false

        Disables CLAT on interface 6 of CLIENT4 without asking. Refused if CLIENT4 is in automatic mode.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Set-WinClatInstance -InterfaceAlias 'Ethernet' -State Enabled | Export-Csv -Path .\WinClatChanges.csv -NoTypeInformation -Append

        Enables CLAT manually on the Ethernet adapter of each computer in clients.txt, after confirmation, and appends the results to WinClatChanges.csv as a record of the change.

    .EXAMPLE
        Set-WinClatConfiguration -ComputerName CLIENT4 -AutoEnable Disabled -Confirm:$false
        Set-WinClatInstance -ComputerName CLIENT4 -InterfaceAlias 'Ethernet' -State Disabled -Confirm:$false
        Set-WinClatConfiguration -ComputerName CLIENT4 -AutoEnable Enabled

        Returns the Ethernet adapter of CLIENT4 from a manually enabled instance to automatic control. A manually enabled instance keeps running when AutoEnable is enabled, and -State Disabled is refused while AutoEnable is enabled, so AutoEnable is disabled first. That briefly stops CLAT on every automatically enabled interface of CLIENT4. When AutoEnable is enabled again, Windows starts CLAT on each eligible interface: within about a second on networks whose router advertisements carry the PREF64 option, and after about 10 seconds on networks without it.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Get-WinClatInstance | Where-Object -FilterScript { $_.Mode -eq 'Manual' -and $_.Enabled } | Format-Table -Property ComputerName, InterfaceAlias, IsTranslating, TriggerSource

        Lists the manually enabled instances on the computers in clients.txt, to see where the previous example is needed. Disabled instances are left out, because every instance reports Mode Manual while AutoEnable is disabled.

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

        See docs/DESIGN.md, section 7.4.

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByAlias', PositionalBinding = $false)]
    [OutputType('WinClat.SetResult')]

    Param (

        [Parameter(Mandatory, ParameterSetName = 'ByAlias')]
        [ValidateNotNullOrEmpty()]
        [string]$InterfaceAlias,

        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory)]
        [ValidateSet('Enabled', 'Disabled')]
        [string]$State,
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
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

        # ValidateSet accepts any case; netsh and the results use the canonical spelling.
        $WinClatState = 'Disabled'

        If ($State -eq 'Enabled') {

            $WinClatState = 'Enabled'

        }

        # The interface as selected, for rows of computers that never reached the adapter lookup.
        $SelectedAlias = $null
        $SelectedIndex = $null
        $AliasArgument = ''
        $IndexArgument = 0

        If ($PSCmdlet.ParameterSetName -eq 'ByAlias') {

            $SelectedAlias = $InterfaceAlias
            $AliasArgument = $InterfaceAlias

        }

        Else {

            $SelectedIndex = $InterfaceIndex
            $IndexArgument = $InterfaceIndex

        }

        $NewFailure = {

            Param ($Name, $Status, $Message)

            ConvertTo-WinClatSetResult -ComputerName $Name -Status $Status -Setting 'State' -InterfaceAlias $SelectedAlias -InterfaceIndex $SelectedIndex -RequestedValue $WinClatState -Message $Message

        }

        $RemoteParameters = @{

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

        # Pass 1: find and check the adapter and read the current state. Refusals are returned as SetResult rows.
        $Plans = [ordered]@{}

        ForEach ($Row in @(Invoke-WinClatRemote @RemoteParameters -ComputerName $Targets.ToArray() -ScriptBlock (Get-WinClatInstancePlanScript) -ArgumentList @($AliasArgument, $IndexArgument, $WinClatState))) {

            If ($Row.PSObject.TypeNames[0] -eq 'WinClat.InstancePlan') {

                $Plans[[string]$Row.ComputerName] = $Row

            }

            Else {

                $Row | Measure-WinClatResult -Tally $Tally

            }

        }

        # Confirm on the calling computer, one decision per computer. Computers that need autoenable disabled are changed in their own batch.
        $WithAutoEnable = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $WithoutAutoEnable = New-Object -TypeName 'System.Collections.Generic.List[string]'

        ForEach ($Key in $Plans.Keys) {

            $Plan = $Plans[$Key]
            $DisableAutoEnable = $WinClatState -eq 'Enabled' -and $Plan.AutoEnable -eq $true
            $Current = $Plan.CurrentState

            If (-not $Current) {

                $Current = 'unknown'

            }

            $Action = "Disable WinCLAT (currently $Current)."

            If ($WinClatState -eq 'Enabled') {

                $Action = "Enable WinCLAT manually (currently $Current). Manual state is lost on reboot."

            }

            If ($DisableAutoEnable) {

                $Action += ' AutoEnable is enabled and will be disabled first, which stops CLAT on every interface where it was automatically enabled.'

            }

            If ($PSCmdlet.ShouldProcess("$Key, interface $($Plan.InterfaceAlias) (index $($Plan.InterfaceIndex))", $Action)) {

                If ($DisableAutoEnable) {

                    $WithAutoEnable.Add($Key)

                }

                Else {

                    $WithoutAutoEnable.Add($Key)

                }

            }

        }

        # Pass 2: change the confirmed computers and read the instance back.
        $Batches = @(

            @{ Computers = $WithoutAutoEnable; DisableAutoEnable = $false }
            @{ Computers = $WithAutoEnable; DisableAutoEnable = $true }

        )

        ForEach ($Batch in $Batches) {

            If ($Batch.Computers.Count -eq 0) {

                Continue

            }

            $Arguments = @($AliasArgument, $IndexArgument, $WinClatState, $Batch.DisableAutoEnable)

            ForEach ($Row in @(Invoke-WinClatRemote @RemoteParameters -ComputerName $Batch.Computers.ToArray() -ScriptBlock (Get-WinClatSetInstanceScript) -ArgumentList $Arguments)) {

                $Row | Measure-WinClatResult -Tally $Tally

                If ($Row.Setting -eq 'State' -and $Row.Status -eq 'Success' -and $WinClatState -eq 'Enabled') {

                    Write-Warning -Message "$($Row.ComputerName): Manual CLAT state on $($Row.InterfaceAlias) is lost on reboot, and AutoEnable stays disabled. After a restart, CLAT will not activate until you run Set-WinClatConfiguration -AutoEnable Enabled or enable the instance again."

                }

            }

        }

        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'changed' -Cmdlet $PSCmdlet

    }

}
