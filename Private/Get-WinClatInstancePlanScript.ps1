Function Get-WinClatInstancePlanScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Set-WinClatInstance runs on each target before asking for confirmation.

    .DESCRIPTION
        The read pass of Set-WinClatInstance (DESIGN.md, section 7.4). The script block takes three positional arguments: the exact InterfaceAlias (empty when selecting by index), the InterfaceIndex (0 when selecting by alias), and the requested State ('Enabled' or 'Disabled'). It changes nothing.

        It returns either one WinClat.SetResult row explaining why the computer is refused, or one WinClat.InstancePlan object used for the confirmation message:
          1. Feature check, then elevation check (section 4.4). Reading instance state requires elevation.
          2. Finds and checks the adapter with Get-WinClatTargetAdapter: missing, not up, and IPv6-unbound adapters are refused.
          3. Reads the active permit and autoenable values. -State Enabled is refused while permit is disabled, because netsh refuses the enable with 'CLAT not permitted.' (section 10), and the message says how to permit CLAT. -State Disabled is refused while autoenable is enabled, because netsh refuses 'set instance' in automatic mode and turning autoenable off would stop CLAT on every automatically enabled interface. When the IPxlatCfg event log shows the instance was enabled manually, the message explains that turning autoenable off does not stop it.
          4. Reads the current instance state.

        Set-WinClatInstance and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatInstancePlanScript) 'Internal' 0 'Enabled'

        Returns the plan for enabling CLAT on the Internal adapter of the local computer.

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

    #>

    [CmdletBinding()]
    [OutputType([scriptblock])]

    Param ()

    $HelperName = @(

        'ConvertFrom-WinClatNetshOutput'
        'ConvertTo-WinClatTimeSpan'
        'ConvertTo-WinClatSetResult'
        'Get-WinClatNetshFailure'
        'Get-WinClatPermitRefusal'
        'Get-WinClatPolicyControlled'
        'Get-WinClatTargetAdapter'
        'Get-WinClatTriggerSource'
        'Test-WinClatElevation'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'

    )

    $Body = {

        Param ($InterfaceAlias, $InterfaceIndex, $State)

        $Refuse = {

            Param ($Status, $Message, $Alias, $Index)

            $Row = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $Status
                Setting        = 'State'
                InterfaceAlias = $Alias
                InterfaceIndex = $Index
                RequestedValue = $State
                Message        = $Message

            }

            ConvertTo-WinClatSetResult @Row

        }

        # Report the interface as the caller selected it until the adapter is found.
        $SelectedAlias = $null
        $SelectedIndex = $null

        If ($InterfaceAlias) {

            $SelectedAlias = $InterfaceAlias

        }

        Else {

            $SelectedIndex = [int]$InterfaceIndex

        }

        If (-not (Test-WinClatFeature -InputObject @(netsh.exe interface '?'))) {

            $Missing = Get-WinClatFeatureFailure
            & $Refuse $Missing.Status $Missing.Message $SelectedAlias $SelectedIndex
            Return

        }

        If (-not (Test-WinClatElevation)) {

            & $Refuse 'ElevationRequired' 'Changing a WinCLAT instance requires an elevated session. Run PowerShell as administrator, or connect with an account that is a local administrator on the target.' $SelectedAlias $SelectedIndex
            Return

        }

        $Target = Get-WinClatTargetAdapter -InterfaceAlias $InterfaceAlias -InterfaceIndex ([int]$InterfaceIndex)

        If ($Target.Problem) {

            & $Refuse 'Failed' $Target.Problem $Target.InterfaceAlias $Target.InterfaceIndex
            Return

        }

        $GlobalOutput = @(netsh.exe interface clat show global)
        $ExitCode = $LASTEXITCODE
        $GlobalSettings = $null

        If ($ExitCode -eq 0) {

            $GlobalSettings = @(ConvertFrom-WinClatNetshOutput -InputObject $GlobalOutput)[0]

        }

        If (-not $GlobalSettings -or $GlobalSettings.AutoEnable -isnot [bool]) {

            & $Refuse 'Failed' "The global configuration could not be read, so nothing was changed: $((@($GlobalOutput) -join ' ').Trim())" $Target.InterfaceAlias $Target.InterfaceIndex
            Return

        }

        # netsh refuses a manual enable while permit is disabled (section 10). Refusing here means autoenable is never
        # disabled for an enable that cannot succeed.
        If ($State -eq 'Enabled' -and $GlobalSettings.Permit -eq $false) {

            & $Refuse 'Failed' (Get-WinClatPermitRefusal) $Target.InterfaceAlias $Target.InterfaceIndex
            Return

        }

        If ($State -eq 'Disabled' -and $GlobalSettings.AutoEnable) {

            $Message = 'CLAT is in automatic mode, so a single interface cannot be disabled; netsh refuses the change while AutoEnable is enabled. Run Set-WinClatConfiguration -AutoEnable Disabled to stop CLAT on every automatically enabled interface.'

            # A manually enabled instance keeps running when autoenable is turned off, so that advice alone would not stop it.
            If ($Target.InterfaceLuid -and (Get-WinClatTriggerSource)[[string]$Target.InterfaceLuid] -eq 'Manual') {

                $Message = 'CLAT on this interface was enabled manually and keeps running in automatic mode; netsh refuses the change while AutoEnable is enabled, and Set-WinClatConfiguration -AutoEnable Disabled does not stop a manually enabled instance. To disable it, run Set-WinClatConfiguration -AutoEnable Disabled and then Set-WinClatInstance -State Disabled. Enabling AutoEnable again starts CLAT automatically on eligible interfaces.'

            }

            & $Refuse 'Failed' $Message $Target.InterfaceAlias $Target.InterfaceIndex
            Return

        }

        $InstanceOutput = @(netsh.exe interface clat show instance "interface=$($Target.InterfaceIndex)")
        $ExitCode = $LASTEXITCODE

        If ($ExitCode -ne 0) {

            $Classified = Get-WinClatNetshFailure -InputObject $InstanceOutput -ExitCode $ExitCode
            & $Refuse $Classified.Status $Classified.Message $Target.InterfaceAlias $Target.InterfaceIndex
            Return

        }

        $Instance = @(ConvertFrom-WinClatNetshOutput -InputObject $InstanceOutput)[0]
        $CurrentState = $null

        If ($Instance -and $Instance.Enabled -is [bool]) {

            $CurrentState = 'Disabled'

            If ($Instance.Enabled) {

                $CurrentState = 'Enabled'

            }

        }

        [PSCustomObject]@{

            PSTypeName     = 'WinClat.InstancePlan'
            ComputerName   = $env:COMPUTERNAME
            Status         = 'Success'
            InterfaceAlias = $Target.InterfaceAlias
            InterfaceIndex = $Target.InterfaceIndex
            AutoEnable     = $GlobalSettings.AutoEnable
            CurrentState   = $CurrentState

        }

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
