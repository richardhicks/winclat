Function Get-WinClatSetInstanceScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Set-WinClatInstance runs on each confirmed target.

    .DESCRIPTION
        The change pass of Set-WinClatInstance (DESIGN.md, section 7.4). The script block takes four positional arguments: the exact InterfaceAlias (empty when selecting by index), the InterfaceIndex (0 when selecting by alias), the requested State ('Enabled' or 'Disabled'), and whether autoenable may be disabled first ([bool], confirmed by the caller).

        It returns WinClat.SetResult rows:
          1. Feature and elevation checks, then the adapter is found and checked again, because the computer may have changed since it was confirmed.
          2. -State Enabled is refused, with nothing changed, when permit is disabled in the active store.
          3. When autoenable is enabled: if the caller confirmed disabling it, 'set global autoenable=disabled' runs and is verified, and an 'AutoEnable' row is returned. Otherwise nothing is changed, because the confirmation no longer describes the computer.
          4. 'set instance interface=<ifIndex> state=<State>' runs, and the instance is read back. The 'State' row is Success when the instance state matches the request. Translation can take several seconds to start after a manual enable (section 10), so translating is not required.

        netsh informational output is written to the verbose stream.

        Set-WinClatInstance and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatSetInstanceScript) 'Internal' 0 'Enabled' $true

        Disables autoenable if it is enabled, then enables CLAT on the Internal adapter of the local computer.

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
        'Test-WinClatElevation'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'

    )

    $Body = {

        Param ($InterfaceAlias, $InterfaceIndex, $State, $DisableAutoEnable)

        $SelectedAlias = $null
        $SelectedIndex = $null

        If ($InterfaceAlias) {

            $SelectedAlias = $InterfaceAlias

        }

        Else {

            $SelectedIndex = [int]$InterfaceIndex

        }

        $StateRow = {

            Param ($Status, $Message, $Alias, $Index, $Effective, $Changed)

            $Row = @{

                ComputerName          = $env:COMPUTERNAME
                Status                = $Status
                Setting               = 'State'
                InterfaceAlias        = $Alias
                InterfaceIndex        = $Index
                RequestedValue        = $State
                EffectiveValue        = $Effective
                PolicyControlled      = $false
                EffectiveValueChanged = $Changed
                Message               = $Message

            }

            ConvertTo-WinClatSetResult @Row

        }

        $WriteVerbose = {

            Param ($Output)

            ForEach ($Line in $Output) {

                If ("$Line".Trim()) {

                    Write-Verbose -Message "$($env:COMPUTERNAME): $("$Line".Trim())"

                }

            }

        }

        # The instance state as 'Enabled' or 'Disabled', or $null when it cannot be read.
        $ReadState = {

            Param ($Index)

            $Output = @(netsh.exe interface clat show instance "interface=$Index")

            If ($LASTEXITCODE -eq 0) {

                $Instance = @(ConvertFrom-WinClatNetshOutput -InputObject $Output)[0]

                If ($Instance -and $Instance.Enabled -is [bool]) {

                    If ($Instance.Enabled) {

                        'Enabled'

                    }

                    Else {

                        'Disabled'

                    }

                }

            }

        }

        $ReadGlobal = {

            $Output = @(netsh.exe interface clat show global 'store=both')

            If ($LASTEXITCODE -eq 0) {

                @(ConvertFrom-WinClatNetshOutput -InputObject $Output)

            }

        }

        If (-not (Test-WinClatFeature -InputObject @(netsh.exe interface '?'))) {

            $Missing = Get-WinClatFeatureFailure
            & $StateRow $Missing.Status $Missing.Message $SelectedAlias $SelectedIndex $null $null
            Return

        }

        If (-not (Test-WinClatElevation)) {

            & $StateRow 'ElevationRequired' 'Changing a WinCLAT instance requires an elevated session. Run PowerShell as administrator, or connect with an account that is a local administrator on the target.' $SelectedAlias $SelectedIndex $null $null
            Return

        }

        $Target = Get-WinClatTargetAdapter -InterfaceAlias $InterfaceAlias -InterfaceIndex ([int]$InterfaceIndex)

        If ($Target.Problem) {

            & $StateRow 'Failed' $Target.Problem $Target.InterfaceAlias $Target.InterfaceIndex $null $null
            Return

        }

        $Alias = $Target.InterfaceAlias
        $Index = $Target.InterfaceIndex
        $Active = @(@(& $ReadGlobal) | Where-Object -FilterScript { $_.Store -eq 'Active' })[0]

        If (-not $Active -or $Active.AutoEnable -isnot [bool]) {

            & $StateRow 'Failed' 'The global configuration could not be read, so nothing was changed.' $Alias $Index $null $null
            Return

        }

        # Checked again, because permit may have been disabled since the read pass; autoenable is not touched.
        If ($State -eq 'Enabled' -and $Active.Permit -eq $false) {

            & $StateRow 'Failed' (Get-WinClatPermitRefusal) $Alias $Index $null $null
            Return

        }

        If ($Active.AutoEnable) {

            If ($State -ne 'Enabled' -or -not $DisableAutoEnable) {

                & $StateRow 'Failed' 'AutoEnable is enabled on this computer, which no longer matches what was confirmed, so nothing was changed. Run the command again.' $Alias $Index $null $null
                Return

            }

            # Disable autoenable first; netsh refuses 'set instance' in automatic mode (section 10).
            $Output = @(netsh.exe interface clat set global 'autoenable=disabled')
            $ExitCode = $LASTEXITCODE
            & $WriteVerbose $Output

            $AutoEnableRow = @{

                ComputerName          = $env:COMPUTERNAME
                Status                = 'Success'
                Setting               = 'AutoEnable'
                RequestedValue        = $false
                PolicyControlled      = $false
                EffectiveValueChanged = $null
                Message               = $null

            }

            If ($ExitCode -ne 0) {

                $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode
                $AutoEnableRow['Status'] = $Classified.Status
                $AutoEnableRow['Message'] = $Classified.Message
                ConvertTo-WinClatSetResult @AutoEnableRow
                & $StateRow 'Failed' 'The instance was not changed because AutoEnable could not be disabled.' $Alias $Index $null $null
                Return

            }

            $After = @(& $ReadGlobal)
            $AfterActive = @($After | Where-Object -FilterScript { $_.Store -eq 'Active' })[0]
            $AfterPersistent = @($After | Where-Object -FilterScript { $_.Store -eq 'Persistent' })[0]

            If ($AfterActive) {

                $AutoEnableRow['EffectiveValue'] = $AfterActive.AutoEnable
                $AutoEnableRow['EffectiveValueChanged'] = $AfterActive.AutoEnable -ne $true

            }

            If ($AfterPersistent) {

                $AutoEnableRow['PersistentValue'] = $AfterPersistent.AutoEnable

            }

            If (-not $AfterActive -or $AfterActive.AutoEnable -ne $false) {

                $AutoEnableRow['Status'] = 'Failed'
                $AutoEnableRow['Message'] = 'netsh.exe reported success, but AutoEnable is still enabled.'
                ConvertTo-WinClatSetResult @AutoEnableRow
                & $StateRow 'Failed' 'The instance was not changed because AutoEnable could not be disabled.' $Alias $Index $null $null
                Return

            }

            $AutoEnableRow['Message'] = 'Disabled so that the instance could be enabled manually. CLAT was stopped on every interface where it was automatically enabled.'
            ConvertTo-WinClatSetResult @AutoEnableRow

        }

        $Before = & $ReadState $Index
        $Output = @(netsh.exe interface clat set instance "interface=$Index" "state=$($State.ToLowerInvariant())")
        $ExitCode = $LASTEXITCODE
        & $WriteVerbose $Output

        If ($ExitCode -ne 0) {

            $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode
            & $StateRow $Classified.Status $Classified.Message $Alias $Index $Before $false
            Return

        }

        # set instance prints nothing on success, so read the instance back (section 7.4).
        $After = & $ReadState $Index
        $Changed = $null

        If ($Before -and $After) {

            $Changed = $After -ne $Before

        }

        If ($After -eq $State) {

            & $StateRow 'Success' $null $Alias $Index $After $Changed

        }

        ElseIf ($After) {

            & $StateRow 'Failed' "netsh.exe reported success, but the instance state is $After." $Alias $Index $After $Changed

        }

        Else {

            & $StateRow 'Failed' 'netsh.exe reported success, but the instance state could not be read back to verify the change.' $Alias $Index $null $null

        }

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
