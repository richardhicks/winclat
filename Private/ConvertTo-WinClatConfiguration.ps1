Function ConvertTo-WinClatConfiguration {

    <#

    .SYNOPSIS
        Builds a WinClat.Configuration output object.

    .DESCRIPTION
        Creates a WinClat.Configuration object with the properties from DESIGN.md, section 6, in a fixed order, so success and failure rows have the same columns for Export-Csv.

        Used on the target to convert parsed 'show global' output, and by Get-WinClatConfiguration to build Unreachable results.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER ComputerName
        The computer name. Invoke-WinClatRemote replaces it with the name as supplied by the caller.

    .PARAMETER Status
        One of the status values in DESIGN.md, section 4.5.

    .PARAMETER Settings
        A parsed 'show global' block from ConvertFrom-WinClatNetshOutput. Omit for failures.

    .PARAMETER PolicyControlled
        The comma-separated list of settings that Group Policy controls.

    .PARAMETER OSBuild
        The operating system version including the update build revision.

    .PARAMETER CollectedAtUtc
        The UTC time the data was collected.

    .PARAMETER Message
        Detail for failures, or $null.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.Configuration.

    .EXAMPLE
        ConvertTo-WinClatConfiguration -ComputerName 'CLIENT4' -Status 'Unreachable' -Message 'WinRM cannot complete the operation.' -CollectedAtUtc (Get-Date).ToUniversalTime()

        Returns a WinClat.Configuration object with Status Unreachable and no settings.

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
    [OutputType('WinClat.Configuration')]

    Param (

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Status,

        [PSObject]$Settings,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$PolicyControlled,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$OSBuild,

        [AllowNull()]
        [object]$CollectedAtUtc,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message

    )

    $Value = @{}

    ForEach ($Name in @('Store', 'Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')) {

        $Value[$Name] = $null

        If ($Settings -and $Settings.PSObject.Properties[$Name]) {

            $Value[$Name] = $Settings.$Name

        }

    }

    # [string] parameters turn $null into ''; keep $null for values that were not supplied.
    $Result = [ordered]@{

        PSTypeName       = 'WinClat.Configuration'
        ComputerName     = $ComputerName
        Status           = $Status
        Store            = $Value['Store']
        Permit           = $Value['Permit']
        Pref64FromDns    = $Value['Pref64FromDns']
        Pref64FromRA     = $Value['Pref64FromRA']
        AutoEnable       = $Value['AutoEnable']
        PolicyControlled = $null
        OSBuild          = $null
        CollectedAtUtc   = $CollectedAtUtc
        Message          = $null

    }

    If ($PSBoundParameters.ContainsKey('PolicyControlled')) {

        $Result['PolicyControlled'] = $PolicyControlled

    }

    If ($OSBuild) {

        $Result['OSBuild'] = $OSBuild

    }

    If ($Message) {

        $Result['Message'] = $Message

    }

    [PSCustomObject]$Result

}
