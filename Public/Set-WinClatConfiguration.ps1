Function Set-WinClatConfiguration {

    <#

    .SYNOPSIS
        Changes global Windows CLAT (WinCLAT) configuration.

    .DESCRIPTION
        Wraps 'netsh.exe interface clat set global'. Only the settings you supply are changed, and every computer returns one WinClat.SetResult object per setting. Runs locally or against one or more remote computers in parallel. Requires elevation on the target computer.

        Before changing anything, the current configuration of every computer is read, so that:
          - A change that would leave both Pref64FromRA and Pref64FromDns disabled is refused with Status Failed, because CLAT would never activate. netsh accepts that combination silently.
          - The confirmation message names any requested setting that Group Policy controls.

        Settings that Group Policy controls are still written locally, so they take effect if the policy is removed. When the policy keeps the effective value different from the request, the result has Status PolicyOverride and EffectiveValueChanged $false, and a warning is written for each computer and setting.

        netsh reports success even when policy prevents a change, so the configuration is always read back after the change, and the result reports both the persistent (local) and effective (active) values.

        Disabling AutoEnable or Permit disables CLAT on every interface where it was automatically enabled, so -AutoEnable Disabled and -Permit Disabled ask for confirmation unless -Confirm:$false is supplied. Instances enabled manually with Set-WinClatInstance keep running in both cases; disable them with Set-WinClatInstance -State Disabled. Other changes do not ask by default. Re-enabling AutoEnable reactivates CLAT within about a second on networks whose router advertisements carry the PREF64 option, and after about 10 seconds on networks without it, where Windows first waits to conclude that the interface has no IPv4; use Get-WinClatInstance to check.

        The function does not write a log. Each result object records the requested, persistent, and effective values, so piping the results to Export-Csv keeps a complete record of a run (see the examples). PowerShell script block logging or transcription enabled by policy also records each call. Windows does not log global configuration changes, but it logs their effect on each instance (enabled, disabled, translation started and stopped) in the Microsoft-Windows-IPxlatCfg/Operational event log on the target.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

    .PARAMETER Permit
        Enabled or Disabled: whether CLAT is permitted on non-cellular interfaces. Disabling it disables CLAT on every interface where it was automatically enabled, blocks new manual enables with Set-WinClatInstance, and asks for confirmation. A manually enabled instance that is already running keeps translating. To stop it, disable AutoEnable and then run Set-WinClatInstance -State Disabled.

    .PARAMETER Pref64FromDns
        Enabled or Disabled: whether to discover the NAT64 prefix using DNS (ipv4only.arpa). Used as a fallback when Pref64FromRA is also enabled.

    .PARAMETER Pref64FromRA
        Enabled or Disabled: whether to discover the NAT64 prefix from the PREF64 option in router advertisements.

    .PARAMETER AutoEnable
        Enabled or Disabled: whether CLAT enables automatically on eligible interfaces. Disabling it disables CLAT on every interface where it was automatically enabled, and asks for confirmation.

    .PARAMETER ComputerName
        One or more computers to configure. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

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
        Set-WinClatConfiguration -Permit Enabled

        Permits CLAT on non-cellular interfaces on the local computer.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Set-WinClatConfiguration -Pref64FromDns Disabled -WhatIf

        Shows what would change on each computer in clients.txt without changing anything. Computers where Pref64FromRA is disabled are refused, because both discovery methods would be off.

    .EXAMPLE
        Set-WinClatConfiguration -ComputerName CLIENT4 -AutoEnable Disabled -Confirm:$false

        Switches CLIENT4 to manual mode without asking for confirmation. CLAT stops on every automatically enabled interface.

    .EXAMPLE
        Get-ADComputer -Filter 'Name -like "LAB*"' | Set-WinClatConfiguration -Permit Enabled | Export-Csv -Path .\WinClatChanges.csv -NoTypeInformation -Append

        Permits CLAT on every LAB computer in Active Directory and appends the results, including any PolicyOverride or Unreachable rows, to WinClatChanges.csv as a record of the change.

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

        See docs/DESIGN.md, section 7.3.

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    [OutputType('WinClat.SetResult')]

    Param (

        # Enabled or Disabled, like Set-WinClatInstance -State and netsh itself (DESIGN.md, section 7.3).
        [ValidateSet('Enabled', 'Disabled')]
        [string]$Permit,

        [ValidateSet('Enabled', 'Disabled')]
        [string]$Pref64FromDns,

        [ValidateSet('Enabled', 'Disabled')]
        [string]$Pref64FromRA,

        [ValidateSet('Enabled', 'Disabled')]
        [string]$AutoEnable,

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DNSHostName', 'CN', 'Name')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [PSCredential]$Credential,

        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit = 32

    )

    Begin {

        $SettingOrder = @('Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')

        # A plain hashtable, so ContainsKey works on the target whether it arrives deserialized or in a local runspace.
        $WinClatRequested = @{}

        ForEach ($Setting in $SettingOrder) {

            If ($PSBoundParameters.ContainsKey($Setting)) {

                # The plan and the target work with [bool]; ValidateSet already ignores case.
                $WinClatRequested[$Setting] = $PSBoundParameters[$Setting] -eq 'Enabled'

            }

        }

        If ($WinClatRequested.Count -eq 0) {

            $Exception = New-Object -TypeName System.ArgumentException -ArgumentList 'Specify at least one of -Permit, -Pref64FromDns, -Pref64FromRA, or -AutoEnable.'
            $PSCmdlet.ThrowTerminatingError((New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $Exception, 'WinClatNoSetting', 'InvalidArgument', $null))

        }

        # Disabling AutoEnable or Permit stops CLAT on every automatically enabled interface (DESIGN.md, section 10), so it
        # confirms like ConfirmImpact High. Lowering the threshold in this scope only prompts by default; -Confirm:$false sets
        # it to None and is unaffected.
        $Disables = $false

        ForEach ($Setting in @('AutoEnable', 'Permit')) {

            If ($WinClatRequested.ContainsKey($Setting) -and -not $WinClatRequested[$Setting]) {

                $Disables = $true

            }

        }

        If ($Disables -and $ConfirmPreference -eq 'High') {

            $ConfirmPreference = 'Medium'

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

        # Pass 1: read and validate every computer. Computers that cannot be changed return their rows and errors here.
        $Confirmed = New-Object -TypeName 'System.Collections.Generic.List[object]'

        ForEach ($Item in @(Get-WinClatConfigurationPlan @Shared -ComputerName $Targets.ToArray() -Requested $WinClatRequested)) {

            If ($Item.PSObject.TypeNames[0] -ne 'WinClat.ConfigurationPlan') {

                $Item | Measure-WinClatResult -Tally $Tally
                Continue

            }

            # Confirm on the calling computer, one decision per computer.
            If ($PSCmdlet.ShouldProcess($Item.ComputerName, $Item.Action)) {

                $Confirmed.Add($Item)

            }

        }

        # Pass 2: change the confirmed computers and verify by reading the configuration back.
        If ($Confirmed.Count -gt 0) {

            Invoke-WinClatConfigurationChange @Shared -Plan $Confirmed.ToArray() | Measure-WinClatResult -Tally $Tally

        }

        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'changed' -Cmdlet $PSCmdlet

    }

}
