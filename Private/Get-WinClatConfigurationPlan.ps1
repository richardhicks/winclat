Function Get-WinClatConfigurationPlan {

    <#

    .SYNOPSIS
        Reads the current configuration of every computer and plans a global configuration change for each (pass 1).

    .DESCRIPTION
        The read pass shared by Set-WinClatConfiguration, Import-WinClatConfiguration, and Reset-WinClatConfiguration (DESIGN.md, sections 7.3, 7.7, and 7.8). It runs the Get-WinClatConfiguration script with store=both on every computer, then on the calling computer:
          - Returns WinClat.SetResult failure rows, one per requested setting, for computers that are unreachable, lack the feature, or could not be read. Their Status and Message carry the outcome; no error is written (DESIGN.md, section 4.6).
          - With -OnlyChanged, drops each requested setting whose persistent value already matches; those settings are reported as Unchanged.
          - Refuses a change that would leave both Pref64FromRA and Pref64FromDns disabled in the active store, with Failed rows.
          - Returns one WinClat.ConfigurationPlan object per remaining computer with the settings to write, the unchanged settings, the reported settings (-Report), the active and persistent rows, and the ShouldProcess action text, which names policy-controlled settings and warns when AutoEnable or Permit is disabled.

        Confirmation is left to the public function, because the -AutoEnable Disabled prompt depends on its $ConfirmPreference. WinClat.ConfigurationPlan is internal and is never returned to the caller.

    .PARAMETER ComputerName
        The target computers, as supplied by the caller.

    .PARAMETER Requested
        The settings requested for every computer, as a hashtable of setting name to [bool].

    .PARAMETER RequestByComputer
        Settings requested per computer, keyed by computer name. A computer listed here uses its own settings instead of -Requested.

    .PARAMETER OnlyChanged
        Plan only the settings whose persistent value differs from the request.

    .PARAMETER Report
        Settings that are not requested but are reported with their current values, as a hashtable of setting name to the message for their row. Used by Reset-WinClatConfiguration for Permit when -Permit is not given (DESIGN.md, section 7.8). A setting that is also requested is not reported.

    .PARAMETER Credential
        Credentials used to connect to remote computers.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections.

    .PARAMETER Cmdlet
        The $PSCmdlet of the public function, passed on to Invoke-WinClatRemote.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.SetResult for computers that cannot be changed, and WinClat.ConfigurationPlan for the others.

    .EXAMPLE
        Get-WinClatConfigurationPlan -ComputerName 'CLIENT1' -Requested @{ Permit = $true } -Cmdlet $PSCmdlet

        Returns the plan for permitting CLAT on CLIENT1.

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
    [OutputType('WinClat.SetResult', 'WinClat.ConfigurationPlan')]

    Param (

        # Blank names and comments are dropped by Invoke-WinClatRemote (DESIGN.md, section 4.2).
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$ComputerName,

        [hashtable]$Requested = @{},

        [hashtable]$RequestByComputer = @{},

        [switch]$OnlyChanged,

        [hashtable]$Report = @{},

        [PSCredential]$Credential,

        [int]$ThrottleLimit = 32,

        [System.Management.Automation.PSCmdlet]$Cmdlet

    )

    If (-not $Cmdlet) {

        $Cmdlet = $PSCmdlet

    }

    $SettingOrder = @('Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')

    # A computer listed in -RequestByComputer uses its own settings; every other computer uses -Requested.
    $Requests = @{ Default = $Requested; ByComputer = $RequestByComputer }

    $GetRequest = {

        Param ($Name)

        If ($Requests.ByComputer.ContainsKey($Name)) {

            Return $Requests.ByComputer[$Name]

        }

        Return $Requests.Default

    }

    # One row per requested setting for a computer where nothing was changed.
    $NewFailure = {

        Param ($Name, $Status, $Message)

        $Request = & $GetRequest $Name

        ForEach ($Setting in $SettingOrder) {

            If ($Request.ContainsKey($Setting)) {

                ConvertTo-WinClatSetResult -ComputerName $Name -Status $Status -Setting $Setting -RequestedValue $Request[$Setting] -Message $Message

            }

        }

    }

    $RemoteParameters = @{

        ComputerName     = $ComputerName
        ScriptBlock      = Get-WinClatConfigurationScript
        ArgumentList     = @('both')
        ThrottleLimit    = $ThrottleLimit
        NewFailureObject = $NewFailure
        Cmdlet           = $Cmdlet

    }

    If ($Credential) {

        $RemoteParameters['Credential'] = $Credential

    }

    # Read every computer. Failures write their errors here.
    $Current = [ordered]@{}

    ForEach ($Row in @(Invoke-WinClatRemote @RemoteParameters)) {

        $Key = [string]$Row.ComputerName

        If (-not $Current.Contains($Key)) {

            $Current[$Key] = New-Object -TypeName 'System.Collections.Generic.List[object]'

        }

        $Current[$Key].Add($Row)

    }

    ForEach ($Key in $Current.Keys) {

        $Rows = $Current[$Key].ToArray()
        $Request = & $GetRequest $Key

        # Unreachable or failed computers already have SetResult rows from the failure builder.
        $SetRows = @($Rows | Where-Object -FilterScript { $_.PSObject.TypeNames[0] -eq 'WinClat.SetResult' })

        If ($SetRows.Count -gt 0) {

            ForEach ($SetRow in $SetRows) {

                $SetRow

            }

            Continue

        }

        $Failure = @($Rows | Where-Object -FilterScript { $_.Status -ne 'Success' })[0]

        If ($Failure) {

            & $NewFailure $Key $Failure.Status $Failure.Message
            Continue

        }

        $Active = @($Rows | Where-Object -FilterScript { $_.Store -eq 'Active' })[0]
        $Persistent = @($Rows | Where-Object -FilterScript { $_.Store -eq 'Persistent' })[0]

        If (-not $Active -or ($OnlyChanged -and -not $Persistent)) {

            $Message = 'The current configuration could not be read, so no change was made.'
            & $NewFailure $Key 'Failed' $Message
            Continue

        }

        # A plain hashtable, so ContainsKey works on the target whether it arrives deserialized or in a local runspace.
        $Change = @{}
        $Unchanged = @{}
        $Reported = @{}

        ForEach ($Setting in $SettingOrder) {

            If (-not $Request.ContainsKey($Setting)) {

                If ($Report.ContainsKey($Setting)) {

                    $Reported[$Setting] = $Report[$Setting]

                }

                Continue

            }

            If ($OnlyChanged -and $Persistent.$Setting -eq $Request[$Setting]) {

                $Unchanged[$Setting] = $Request[$Setting]

            }

            Else {

                $Change[$Setting] = $Request[$Setting]

            }

        }

        # Refuse a change that leaves both prefix discovery methods disabled (DESIGN.md, section 7.3).
        $FromRA = $Active.Pref64FromRA -eq $true
        $FromDns = $Active.Pref64FromDns -eq $true

        If ($Change.ContainsKey('Pref64FromRA')) {

            $FromRA = $Change['Pref64FromRA']

        }

        If ($Change.ContainsKey('Pref64FromDns')) {

            $FromDns = $Change['Pref64FromDns']

        }

        If ($Change.Count -gt 0 -and -not $FromRA -and -not $FromDns) {

            $Message = 'The change was refused because it would leave both Pref64FromRA and Pref64FromDns disabled, and CLAT would never activate. Keep at least one prefix discovery method enabled.'
            & $NewFailure $Key 'Failed' $Message
            Continue

        }

        $Action = $null
        $DisablesAutoEnable = $Change.ContainsKey('AutoEnable') -and -not $Change['AutoEnable']
        $DisablesPermit = $Change.ContainsKey('Permit') -and -not $Change['Permit']

        If ($Change.Count -gt 0) {

            $Changes = ForEach ($Setting in $SettingOrder) {

                If ($Change.ContainsKey($Setting)) {

                    # The words the caller typed, as in Set-WinClatConfiguration -Permit Enabled (DESIGN.md, section 7.3).
                    If ($Change[$Setting]) {

                        "$Setting = Enabled"

                    }

                    Else {

                        "$Setting = Disabled"

                    }

                }

            }

            $Action = "Set WinCLAT global configuration: $(@($Changes) -join ', ')."

            If ($DisablesAutoEnable) {

                $Action += ' Disabling AutoEnable disables CLAT on every interface where it was automatically enabled.'

            }

            If ($DisablesPermit) {

                $Action += ' Disabling Permit disables CLAT on every interface where it was automatically enabled, and no instance can be enabled while it is disabled; a manually enabled instance that is already running keeps translating.'

            }

            $Controlled = @(@($Active.PolicyControlled -split ',\s*') | Where-Object -FilterScript { $_ -and $Change.ContainsKey($_) })

            If ($Controlled.Count -gt 0) {

                $Action += " Group Policy controls $($Controlled -join ', '): the local value will be written but does not take effect while the policy applies."

            }

        }

        [PSCustomObject]@{

            PSTypeName         = 'WinClat.ConfigurationPlan'
            ComputerName       = $Key
            Change             = $Change
            Unchanged          = $Unchanged
            Reported           = $Reported
            Active             = $Active
            Persistent         = $Persistent
            Action             = $Action
            DisablesAutoEnable = $DisablesAutoEnable
            DisablesPermit     = $DisablesPermit

        }

    }

}
