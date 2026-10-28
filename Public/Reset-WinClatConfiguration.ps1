Function Reset-WinClatConfiguration {

    <#

    .SYNOPSIS
        Returns the Windows CLAT (WinCLAT) global configuration to the Windows defaults.

    .DESCRIPTION
        Sets Pref64FromDns, Pref64FromRA, and AutoEnable to enabled, the values Windows uses when the WinCLAT feature arrives, without an export file. Runs locally or against one or more remote computers in parallel. Requires elevation on the target computer.

        Permit is changed only when -Permit is given. Microsoft disables Permit by default today and plans to enable it by default in a future release, so a plain reset leaves Permit as it is and never stops CLAT. Use -Permit Disabled for a full reset to today's defaults, or -Permit Enabled to reset and permit CLAT.

        Only settings whose persistent (local) value differs from the default are written, so the confirmation names only real changes. Every computer that was read returns four WinClat.SetResult rows, in the order Permit, Pref64FromDns, Pref64FromRA, AutoEnable: written settings report the values read back after the change, settings that already matched report Success with the message that they were not written, and without -Permit the Permit row reports its current values with the message 'Not changed; use -Permit to set it.'

        As with Set-WinClatConfiguration, settings that Group Policy controls are written locally and reported as PolicyOverride when the policy keeps a different value, and the configuration is read back after every change. A plain reset and -Permit Enabled do not ask for confirmation by default, because they only switch settings on. When -Permit Disabled would change Permit on any computer in the run, every computer in the run asks, because disabling Permit stops CLAT on every automatically enabled interface.

        Manual instances are not changed. Enabling AutoEnable leaves a manually enabled instance running, and so does disabling Permit. For a clean state, also run Set-WinClatInstance -State Disabled on each manually enabled interface, after disabling AutoEnable.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

        The function does not write a log. Piping the results to Export-Csv keeps a complete record of a run.

    .PARAMETER Permit
        Also sets Permit: Disabled for a full reset to today's Windows defaults, or Enabled to permit CLAT. When omitted, Permit is not changed. Disabling Permit disables CLAT on every interface where it was automatically enabled, blocks new manual enables, and asks for confirmation, but a manually enabled instance that is already running keeps translating.

    .PARAMETER ComputerName
        One or more computers to reset. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

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
        Reset-WinClatConfiguration

        Sets Pref64FromDns, Pref64FromRA, and AutoEnable to enabled on the local computer and leaves Permit unchanged.

    .EXAMPLE
        Reset-WinClatConfiguration -ComputerName CLIENT4 -Permit Disabled

        Returns CLIENT4 to today's Windows defaults, including Permit disabled, after confirmation.

    .EXAMPLE
        Set-WinClatConfiguration -ComputerName CLIENT4 -AutoEnable Disabled -Confirm:$false
        Set-WinClatInstance -ComputerName CLIENT4 -InterfaceAlias 'Ethernet' -State Disabled -Confirm:$false
        Reset-WinClatConfiguration -ComputerName CLIENT4

        Resets CLIENT4 to the Windows defaults with no manually enabled instance left running on its Ethernet adapter. A reset does not change manual instances, and Set-WinClatInstance refuses -State Disabled while AutoEnable is enabled, so AutoEnable is disabled first, which briefly stops CLAT on every automatically enabled interface. The reset then enables AutoEnable again, and Windows starts CLAT on each eligible interface by itself.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Reset-WinClatConfiguration -WhatIf

        Shows which settings a reset would change on each computer in clients.txt, without changing anything.

    .EXAMPLE
        Get-ADComputer -Filter 'Name -like "LAB*"' | Reset-WinClatConfiguration -Permit Enabled | Export-Csv -Path .\WinClatReset.csv -NoTypeInformation

        Resets every LAB computer in Active Directory with CLAT permitted, and records the results in WinClatReset.csv.

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

        See docs/DESIGN.md, section 7.8.

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    [OutputType('WinClat.SetResult')]

    Param (

        # Enabled or Disabled, like Set-WinClatConfiguration (DESIGN.md, section 7.8).
        [ValidateSet('Enabled', 'Disabled')]
        [string]$Permit,

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DNSHostName', 'CN', 'Name')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [PSCredential]$Credential,

        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit = 32

    )

    Begin {

        # The Windows defaults (DESIGN.md, section 7.8). A plain hashtable, so ContainsKey works on the target whether it
        # arrives deserialized or in a local runspace.
        $WinClatRequested = @{

            Pref64FromDns = $true
            Pref64FromRA  = $true
            AutoEnable    = $true

        }

        $Report = @{}

        If ($PSBoundParameters.ContainsKey('Permit')) {

            $WinClatRequested['Permit'] = $Permit -eq 'Enabled'

        }

        Else {

            $Report['Permit'] = 'Not changed; use -Permit to set it.'

        }

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

        $Shared = @{

            ThrottleLimit = $ThrottleLimit
            Cmdlet        = $PSCmdlet

        }

        If ($Credential) {

            $Shared['Credential'] = $Credential

        }

        # One summary warning at the end instead of an error per computer (DESIGN.md, section 4.6). For a single computer the
        # results are held, so exactly one is shown as a list and several as a table (section 6); fleet results still stream.
        $Tally = New-WinClatTally -ComputerName $Targets.ToArray()

        # Pass 1: read every computer, keeping only the settings that differ from the defaults.
        $Items = @(Get-WinClatConfigurationPlan @Shared -ComputerName $Targets.ToArray() -Requested $WinClatRequested -Report $Report -OnlyChanged)

        # Disabling permit stops CLAT on every automatically enabled interface, so the run confirms like ConfirmImpact High.
        # The preference is read at the first ShouldProcess call, so it applies to every computer in the run.
        If (@($Items | Where-Object -FilterScript { $_.PSObject.TypeNames[0] -eq 'WinClat.ConfigurationPlan' -and $_.DisablesPermit }).Count -gt 0 -and $ConfirmPreference -eq 'High') {

            $ConfirmPreference = 'Medium'

        }

        $Unchanged = ''

        If ($Report.ContainsKey('Permit')) {

            $Unchanged = ' Permit is left unchanged; use -Permit to set it.'

        }

        $Run = New-Object -TypeName 'System.Collections.Generic.List[object]'

        ForEach ($Item in $Items) {

            If ($Item.PSObject.TypeNames[0] -ne 'WinClat.ConfigurationPlan') {

                $Item | Measure-WinClatResult -Tally $Tally
                Continue

            }

            # Nothing differs, so there is nothing to confirm; the unchanged rows are still returned.
            If ($Item.Change.Count -eq 0 -or $PSCmdlet.ShouldProcess($Item.ComputerName, "Reset to the Windows defaults. $($Item.Action)$Unchanged")) {

                $Run.Add($Item)

            }

        }

        # Pass 2: change the confirmed computers and verify by reading the configuration back.
        If ($Run.Count -gt 0) {

            Invoke-WinClatConfigurationChange @Shared -Plan $Run.ToArray() | Measure-WinClatResult -Tally $Tally

        }

        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'changed' -Cmdlet $PSCmdlet

    }

}
