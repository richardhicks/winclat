Function ConvertTo-WinClatSetResult {

    <#

    .SYNOPSIS
        Builds a WinClat.SetResult output object.

    .DESCRIPTION
        Creates a WinClat.SetResult object with the properties from DESIGN.md, section 6, in a fixed order, so every row has the same columns for Export-Csv. One object is returned per computer per requested setting.

        Used on the target after a change, and by the Set- functions to build rows for computers that were unreachable, lacked the feature, or were refused before any change was made.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER ComputerName
        The computer name. Invoke-WinClatRemote replaces it with the name as supplied by the caller.

    .PARAMETER Status
        One of the status values in DESIGN.md, section 4.5.

    .PARAMETER Setting
        The setting that was requested, for example 'Permit', or 'State' for an interface.

    .PARAMETER InterfaceAlias
        The adapter name for interface results, or $null for global settings.

    .PARAMETER InterfaceIndex
        The adapter interface index for interface results, or $null for global settings.

    .PARAMETER RequestedValue
        The value that was requested. A [bool] is returned as 'Enabled' or 'Disabled', as are the persistent and effective values.

    .PARAMETER PersistentValue
        The persistent (local) value read after the change, or $null when no change was made.

    .PARAMETER EffectiveValue
        The active (effective) value read after the change, or $null when no change was made.

    .PARAMETER PolicyControlled
        Whether Group Policy controls the setting, or $null when unknown.

    .PARAMETER EffectiveValueChanged
        Whether the effective value differs from its value before the change, or $null when no change was made.

    .PARAMETER Message
        Detail for failures and policy overrides, or $null.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.SetResult.

    .EXAMPLE
        ConvertTo-WinClatSetResult -ComputerName 'CLIENT4' -Status 'Unreachable' -Setting 'Permit' -RequestedValue $true -Message 'WinRM cannot complete the operation.'

        Returns a WinClat.SetResult row recording that the Permit change could not be attempted on CLIENT4.

    .LINK
        https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-pscustomobject

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

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Setting,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$InterfaceAlias,

        [AllowNull()]
        [object]$InterfaceIndex,

        [AllowNull()]
        [object]$RequestedValue,

        [AllowNull()]
        [object]$PersistentValue,

        [AllowNull()]
        [object]$EffectiveValue,

        [AllowNull()]
        [object]$PolicyControlled,

        [AllowNull()]
        [object]$EffectiveValueChanged,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message

    )

    # Global settings are read and requested as [bool]; rows show them as Enabled or Disabled, the values the Set- functions
    # take, so every row uses the same words as a State row (DESIGN.md, section 6).
    $Values = @{ RequestedValue = $RequestedValue; PersistentValue = $PersistentValue; EffectiveValue = $EffectiveValue }

    ForEach ($Key in @($Values.Keys)) {

        If ($Values[$Key] -is [bool]) {

            If ($Values[$Key]) {

                $Values[$Key] = 'Enabled'

            }

            Else {

                $Values[$Key] = 'Disabled'

            }

        }

    }

    # [string] parameters turn $null into ''; keep $null for values that were not supplied.
    $Result = [ordered]@{

        PSTypeName            = 'WinClat.SetResult'
        ComputerName          = $ComputerName
        Status                = $Status
        Setting               = $Setting
        InterfaceAlias        = $null
        InterfaceIndex        = $InterfaceIndex
        RequestedValue        = $Values['RequestedValue']
        PersistentValue       = $Values['PersistentValue']
        EffectiveValue        = $Values['EffectiveValue']
        PolicyControlled      = $PolicyControlled
        EffectiveValueChanged = $EffectiveValueChanged
        Message               = $null

    }

    If ($InterfaceAlias) {

        $Result['InterfaceAlias'] = $InterfaceAlias

    }

    If ($Message) {

        $Result['Message'] = $Message

    }

    [PSCustomObject]$Result

}
