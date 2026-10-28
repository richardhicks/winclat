Function ConvertTo-WinClatTestResult {

    <#

    .SYNOPSIS
        Builds a WinClat.TestResult output object.

    .DESCRIPTION
        Creates a WinClat.TestResult object with the properties from DESIGN.md, section 6, in a fixed order, so every row has the same columns for Export-Csv.

        Status is the target-level status: Success when the checks ran, even if some of them failed, and Unreachable or Failed when they could not run. Result is the outcome of the individual check: Pass, Warning, Fail, Info, or Skipped. Detail carries the message.

        Used on the target for check rows, and by Test-WinClat to build Unreachable results.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER ComputerName
        The computer name. Invoke-WinClatRemote replaces it with the name as supplied by the caller.

    .PARAMETER Status
        The target-level status from DESIGN.md, section 4.5. The default is Success.

    .PARAMETER InterfaceAlias
        The adapter name for interface checks, or $null for computer-wide checks.

    .PARAMETER Check
        The check name, for example 'CLAT permitted'.

    .PARAMETER Result
        Pass, Warning, Fail, Info, or Skipped.

    .PARAMETER Detail
        What was found.

    .PARAMETER Remediation
        What to do about a Warning or Fail result, or $null.

    .PARAMETER CollectedAtUtc
        The UTC time the check ran.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.TestResult.

    .EXAMPLE
        ConvertTo-WinClatTestResult -ComputerName 'CLIENT4' -Check 'CLAT permitted' -Result 'Pass' -Detail 'Permit is enabled in the active store.' -CollectedAtUtc (Get-Date).ToUniversalTime()

        Returns a passing WinClat.TestResult row for CLIENT4.

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
    [OutputType('WinClat.TestResult')]

    Param (

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ComputerName,

        [string]$Status = 'Success',

        [AllowNull()]
        [AllowEmptyString()]
        [string]$InterfaceAlias,

        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warning', 'Fail', 'Info', 'Skipped')]
        [string]$Result,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Detail,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Remediation,

        [AllowNull()]
        [object]$CollectedAtUtc

    )

    # [string] parameters turn $null into ''; keep $null for values that were not supplied.
    $Output = [ordered]@{

        PSTypeName     = 'WinClat.TestResult'
        ComputerName   = $ComputerName
        Status         = $Status
        InterfaceAlias = $null
        Check          = $Check
        Result         = $Result
        Detail         = $null
        Remediation    = $null
        CollectedAtUtc = $CollectedAtUtc

    }

    If ($InterfaceAlias) {

        $Output['InterfaceAlias'] = $InterfaceAlias

    }

    If ($Detail) {

        $Output['Detail'] = $Detail

    }

    If ($Remediation) {

        $Output['Remediation'] = $Remediation

    }

    [PSCustomObject]$Output

}
