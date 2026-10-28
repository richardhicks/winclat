Function ConvertTo-WinClatInstance {

    <#

    .SYNOPSIS
        Builds a WinClat.Instance output object.

    .DESCRIPTION
        Creates a WinClat.Instance object with the properties from DESIGN.md, section 6, in a fixed order, so success and failure rows have the same columns for Export-Csv.

        RemotePrefixRemainingLifetimeRaw is always present, after RemotePrefixRemainingLifetime. It holds the raw netsh string only when the lifetime could not be parsed, and is $null otherwise (section 5.5).

        Without a remote prefix, both lifetime properties are $null, so 'no prefix' looks the same in RemotePrefix and its lifetime, and 00:00:00 always belongs to a prefix whose lifetime has run out, usually at the moment it expires, though an instance that is not translating can keep an expired prefix. netsh prints 0s in that case (section 6).

        Used on the target to convert parsed 'show instance' output, and by Get-WinClatInstance to build Unreachable results.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER ComputerName
        The computer name. Invoke-WinClatRemote replaces it with the name as supplied by the caller.

    .PARAMETER Status
        One of the status values in DESIGN.md, section 4.5.

    .PARAMETER InterfaceAlias
        The adapter name, or $null for results that are not about one adapter.

    .PARAMETER InterfaceIndex
        The adapter interface index, or $null for results that are not about one adapter.

    .PARAMETER Settings
        A parsed 'show instance' block from ConvertFrom-WinClatNetshOutput. Omit for failures.

    .PARAMETER Mode
        Automatic or Manual, or $null when unknown (DESIGN.md, section 6).

    .PARAMETER TriggerSource
        How the instance was enabled, from event 1106 in the IPxlatCfg event log, or $null when the instance is disabled or the event was not found.

    .PARAMETER CollectedAtUtc
        The UTC time the data was collected.

    .PARAMETER Message
        Detail for failures, or $null.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.Instance.

    .EXAMPLE
        ConvertTo-WinClatInstance -ComputerName 'CLIENT4' -Status 'Unreachable' -Message 'WinRM cannot complete the operation.' -CollectedAtUtc (Get-Date).ToUniversalTime()

        Returns a WinClat.Instance object with Status Unreachable and no interface data.

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
    [OutputType('WinClat.Instance')]

    Param (

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Status,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$InterfaceAlias,

        [AllowNull()]
        [object]$InterfaceIndex,

        [PSObject]$Settings,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Mode,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$TriggerSource,

        [AllowNull()]
        [object]$CollectedAtUtc,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message

    )

    $Value = @{}

    ForEach ($Name in @('Enabled', 'IsTranslating', 'LocalPrefix', 'RemotePrefix', 'RemotePrefixRemainingLifetime', 'RemotePrefixRemainingLifetimeRaw', 'IPv6Address', 'IPv4Address')) {

        $Value[$Name] = $null

        If ($Settings -and $Settings.PSObject.Properties[$Name]) {

            $Value[$Name] = $Settings.$Name

        }

    }

    # A lifetime belongs to a remote prefix; without one, netsh's 0s would read as a prefix that just expired.
    If (-not $Value['RemotePrefix']) {

        $Value['RemotePrefixRemainingLifetime'] = $null
        $Value['RemotePrefixRemainingLifetimeRaw'] = $null

    }

    # [string] parameters turn $null into ''; keep $null for values that were not supplied.
    $Result = [ordered]@{

        PSTypeName                       = 'WinClat.Instance'
        ComputerName                     = $ComputerName
        Status                           = $Status
        InterfaceAlias                   = $null
        InterfaceIndex                   = $InterfaceIndex
        Enabled                          = $Value['Enabled']
        IsTranslating                    = $Value['IsTranslating']
        Mode                             = $null
        TriggerSource                    = $null
        LocalPrefix                      = $Value['LocalPrefix']
        RemotePrefix                     = $Value['RemotePrefix']
        RemotePrefixRemainingLifetime    = $Value['RemotePrefixRemainingLifetime']
        RemotePrefixRemainingLifetimeRaw = $Value['RemotePrefixRemainingLifetimeRaw']
        IPv6Address                      = $Value['IPv6Address']
        IPv4Address                      = $Value['IPv4Address']
        CollectedAtUtc                   = $CollectedAtUtc
        Message                          = $null

    }

    If ($InterfaceAlias) {

        $Result['InterfaceAlias'] = $InterfaceAlias

    }

    If ($Mode) {

        $Result['Mode'] = $Mode

    }

    If ($TriggerSource) {

        $Result['TriggerSource'] = $TriggerSource

    }

    If ($Message) {

        $Result['Message'] = $Message

    }

    [PSCustomObject]$Result

}
