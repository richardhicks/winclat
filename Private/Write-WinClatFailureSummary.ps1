Function Write-WinClatFailureSummary {

    <#

    .SYNOPSIS
        Writes one warning at the end of a fleet run when any computer did not complete.

    .DESCRIPTION
        Failures are not written as errors per computer; each result's Status and Message carry the outcome (DESIGN.md, section 4.6). This one-line warning keeps failures from being missed in a long table.

        When every failed computer has the same status, the warning names it:

            WARNING: 4 of 37 computers were unreachable. Use Format-List to see the reason in each result's Message property.

        Failed, which says nothing more than that, uses the action instead: '3 of 37 computers could not be changed.' When the statuses differ, they are listed in the order unreachable, feature not available, elevation required, failed:

            WARNING: 5 of 37 computers could not be changed: 3 unreachable, 1 elevation required, 1 failed. Use Format-List to see the reason in each result's Message property.

        Nothing is written when every computer completed, or when the run was for a single computer, whose result is already on screen with its Status and Message.

    .PARAMETER Tally
        The tally from New-WinClatTally, filled by Measure-WinClatResult.

    .PARAMETER Action
        What the command does to each computer: queried (Get-, Test-, and Export- commands) or changed (Set- and Import- commands). The default is queried.

    .PARAMETER Cmdlet
        The $PSCmdlet of the public function, so the warning is attributed to it and honors its -WarningAction.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. The warning is written to the warning stream.

    .EXAMPLE
        Write-WinClatFailureSummary -Tally $Tally -Action 'changed' -Cmdlet $PSCmdlet

        Writes 'WARNING: 1 of 10 computers was unreachable. ...' when one computer of ten was unreachable.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/write-warning

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
    [OutputType([void])]

    Param (

        [Parameter(Mandatory)]
        [hashtable]$Tally,

        [ValidateSet('queried', 'changed')]
        [string]$Action = 'queried',

        [System.Management.Automation.PSCmdlet]$Cmdlet

    )

    If (-not $Cmdlet) {

        $Cmdlet = $PSCmdlet

    }

    # A single computer's result is already on screen with its Status and Message.
    If ($Tally.Failed.Count -eq 0 -or $Tally.Single) {

        Return

    }

    # The list form, and the predicate for one computer and for several, of each failure status. Failed says nothing
    # more than that, so it uses the action.
    $Phrases = @{

        Unreachable         = @{ List = 'unreachable'; One = 'was unreachable'; Many = 'were unreachable' }
        FeatureNotAvailable = @{ List = 'feature not available'; One = 'does not have the WinCLAT feature'; Many = 'do not have the WinCLAT feature' }
        ElevationRequired   = @{ List = 'elevation required'; One = 'requires elevation'; Many = 'require elevation' }
        Failed              = @{ List = 'failed'; One = "could not be $Action"; Many = "could not be $Action" }

    }

    $Counts = [ordered]@{}

    ForEach ($Status in $Tally.FailureStatus) {

        $Count = @($Tally.Failed.Values | Where-Object -FilterScript { $_ -eq $Status }).Count

        If ($Count -gt 0) {

            $Counts[$Status] = $Count

        }

    }

    $Failed = $Tally.Failed.Count
    $Noun = 'computers'

    If ($Tally.Computers.Count -eq 1) {

        $Noun = 'computer'

    }

    If ($Counts.Count -eq 1) {

        $Status = @($Counts.Keys)[0]
        $Sentence = "$Failed of $($Tally.Computers.Count) $Noun $($Phrases[$Status].Many)."

        If ($Failed -eq 1) {

            $Sentence = "$Failed of $($Tally.Computers.Count) $Noun $($Phrases[$Status].One)."

        }

    }

    Else {

        $Sentence = "$Failed of $($Tally.Computers.Count) $Noun could not be ${Action}: $(@($Counts.Keys | ForEach-Object -Process { "$($Counts[$_]) $($Phrases[$_].List)" }) -join ', ')."

    }

    $Cmdlet.WriteWarning("$Sentence Use Format-List to see the reason in each result's Message property.")

}
