Function Invoke-WinClatConfigurationChange {

    <#

    .SYNOPSIS
        Applies confirmed global configuration plans and returns the verified results (pass 2).

    .DESCRIPTION
        The change pass shared by Set-WinClatConfiguration, Import-WinClatConfiguration, and Reset-WinClatConfiguration (DESIGN.md, sections 7.3, 7.7, and 7.8). Plans come from Get-WinClatConfigurationPlan, after the public function has confirmed them.

        Computers whose plans write the same settings are changed with one Invoke-WinClatRemote call, because it sends the same arguments to every computer in a call. The Set script writes the settings, reads the configuration back, and returns one WinClat.SetResult per setting. A warning is written for every written setting that Group Policy controls.

        Settings that already matched (the plan's Unchanged settings, from -OnlyChanged) are returned as Success rows built from the configuration read in pass 1, with EffectiveValueChanged $false and a message saying they were not written. No warning is written for them, because nothing was written. Reported settings (the plan's Reported settings, from -Report) are returned the same way, with no RequestedValue and the message from the plan.

        When Permit is written as disabled and the change takes effect, the Set script on the target says in the message whether CLAT stopped everywhere or a manually enabled instance is still translating, and how to stop it (DESIGN.md, section 7.3).

        Rows are returned per computer in plan order, with each computer's settings in the order Permit, Pref64FromDns, Pref64FromRA, AutoEnable.

    .PARAMETER Plan
        The WinClat.ConfigurationPlan objects to apply. Plans with no settings to write return only their unchanged rows.

    .PARAMETER Credential
        Credentials used to connect to remote computers.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections.

    .PARAMETER Cmdlet
        The $PSCmdlet of the public function, so errors and warnings are attributed to it.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.SetResult.

    .EXAMPLE
        Invoke-WinClatConfigurationChange -Plan $Confirmed -Cmdlet $PSCmdlet

        Applies the confirmed plans and returns one WinClat.SetResult per computer per setting.

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
    [OutputType('WinClat.SetResult')]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan,

        [PSCredential]$Credential,

        [int]$ThrottleLimit = 32,

        [System.Management.Automation.PSCmdlet]$Cmdlet

    )

    If (-not $Cmdlet) {

        $Cmdlet = $PSCmdlet

    }

    $SettingOrder = @('Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')
    $Results = @{}
    $Batches = [ordered]@{}

    ForEach ($Item in $Plan) {

        $Results[$Item.ComputerName] = New-Object -TypeName 'System.Collections.Generic.List[object]'

        If ($Item.Change.Count -eq 0) {

            Continue

        }

        $Signature = @($SettingOrder | Where-Object -FilterScript { $Item.Change.ContainsKey($_) } | ForEach-Object -Process { "$_=$($Item.Change[$_])" }) -join ';'

        If (-not $Batches.Contains($Signature)) {

            $Batches[$Signature] = @{ Change = $Item.Change; Computers = New-Object -TypeName 'System.Collections.Generic.List[string]' }

        }

        $Batches[$Signature].Computers.Add($Item.ComputerName)

    }

    ForEach ($Batch in $Batches.Values) {

        $Change = $Batch.Change

        # One row per setting for a computer that could not be reached between the two passes. Invoke-WinClatRemote
        # calls it during this iteration, so it reads this batch's $Change.
        $NewFailure = {

            Param ($Name, $Status, $Message)

            ForEach ($Setting in $SettingOrder) {

                If ($Change.ContainsKey($Setting)) {

                    ConvertTo-WinClatSetResult -ComputerName $Name -Status $Status -Setting $Setting -RequestedValue $Change[$Setting] -Message $Message

                }

            }

        }

        $RemoteParameters = @{

            ComputerName     = $Batch.Computers.ToArray()
            ScriptBlock      = Get-WinClatSetConfigurationScript
            ArgumentList     = @($Change)
            ThrottleLimit    = $ThrottleLimit
            NewFailureObject = $NewFailure
            Cmdlet           = $Cmdlet

        }

        If ($Credential) {

            $RemoteParameters['Credential'] = $Credential

        }

        ForEach ($Row in @(Invoke-WinClatRemote @RemoteParameters)) {

            $Key = [string]$Row.ComputerName

            If (-not $Results.ContainsKey($Key)) {

                $Results[$Key] = New-Object -TypeName 'System.Collections.Generic.List[object]'

            }

            $Results[$Key].Add($Row)

        }

    }

    ForEach ($Item in $Plan) {

        $Rows = $Results[$Item.ComputerName]
        $Controlled = @($Item.Active.PolicyControlled -split ',\s*')

        ForEach ($Setting in $SettingOrder) {

            If ($Item.Reported -and $Item.Reported.ContainsKey($Setting)) {

                $Reported = @{

                    ComputerName          = $Item.ComputerName
                    Status                = 'Success'
                    Setting               = $Setting
                    PersistentValue       = $Item.Persistent.$Setting
                    EffectiveValue        = $Item.Active.$Setting
                    PolicyControlled      = $Controlled -contains $Setting
                    EffectiveValueChanged = $false
                    Message               = $Item.Reported[$Setting]

                }

                ConvertTo-WinClatSetResult @Reported

            }

            If ($Item.Unchanged.ContainsKey($Setting)) {

                $Unchanged = @{

                    ComputerName          = $Item.ComputerName
                    Status                = 'Success'
                    Setting               = $Setting
                    RequestedValue        = $Item.Unchanged[$Setting]
                    PersistentValue       = $Item.Persistent.$Setting
                    EffectiveValue        = $Item.Active.$Setting
                    PolicyControlled      = $Controlled -contains $Setting
                    EffectiveValueChanged = $false
                    Message               = 'The persistent value already matches, so it was not written.'

                }

                ConvertTo-WinClatSetResult @Unchanged

            }

            ForEach ($Row in @($Rows | Where-Object -FilterScript { $_.Setting -eq $Setting })) {

                $Row

                If ($Row.PolicyControlled -eq $true) {

                    $Cmdlet.WriteWarning("$($Row.ComputerName): Group Policy controls $($Row.Setting). The local value was written, but the policy decides the effective value (currently $($Row.EffectiveValue)).")

                }

            }

        }

    }

}
