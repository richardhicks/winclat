Function Measure-WinClatResult {

    <#

    .SYNOPSIS
        Passes results through unchanged while counting the computers that did not complete.

    .DESCRIPTION
        Used by every public function on its output, so Write-WinClatFailureSummary can write one summary warning at the end of a run (DESIGN.md, section 4.6). No error is written per computer: each result's Status and Message carry the outcome.

        When the tally is for a single computer, results are held in the tally instead of passed through, so Complete-WinClatResult can show exactly one result as a list and several as a table (DESIGN.md, section 6). -NoHold passes them through anyway, for results that feed further processing, such as the rows Test-WinClat turns into summaries when -Detailed is not given.

        A computer counts as not completed when any of its results has Status Unreachable, FeatureNotAvailable, ElevationRequired, or Failed; the first such status is recorded for it. Success, PolicyOverride (the local value was written), and NotSupported (Windows Server, where WinCLAT is not delivered) are not failures. Objects without a Status are passed through and not counted.

    .PARAMETER InputObject
        A result object from the pipeline.

    .PARAMETER Tally
        A hashtable from New-WinClatTally that collects the computer names and their failure status.

    .PARAMETER NoHold
        Pass results through even when the tally is for a single computer.

    .INPUTS
        System.Management.Automation.PSObject. Result objects.

    .OUTPUTS
        System.Management.Automation.PSObject. The same objects, unchanged, or nothing while they are held for a single computer.

    .EXAMPLE
        Invoke-WinClatRemote @RemoteParameters | Measure-WinClatResult -Tally $Tally

        Returns every result while recording which computers failed.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced

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
    [OutputType([PSObject])]

    Param (

        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [PSObject]$InputObject,

        [Parameter(Mandatory)]
        [hashtable]$Tally,

        [switch]$NoHold

    )

    Process {

        If ($null -eq $InputObject) {

            Return

        }

        $Status = $null

        If ($InputObject.PSObject.Properties['Status']) {

            $Status = [string]$InputObject.Status

        }

        $Name = [string]$InputObject.ComputerName

        If ($Status -and $Name) {

            [void]$Tally.Computers.Add($Name)

            If ($Tally.FailureStatus -contains $Status -and -not $Tally.Failed.ContainsKey($Name)) {

                $Tally.Failed[$Name] = $Status

            }

        }

        If ($Tally.Single -and -not $NoHold) {

            $Tally.Held.Add($InputObject)
            Return

        }

        $InputObject

    }

}
