Function Import-WinClatConfiguration {

    <#

    .SYNOPSIS
        Applies Windows CLAT (WinCLAT) configuration saved by Export-WinClatConfiguration.

    .DESCRIPTION
        Reads files written by Export-WinClatConfiguration and applies their global settings to one or more computers, through the same checks as Set-WinClatConfiguration. The files are never run: each one is parsed strictly, and a file that contains anything other than the comments, 'pushd interface clat', one 'set global' line with the four WinCLAT settings, and 'popd' that netsh writes is refused before any computer is contacted.

        Each file is applied to:
          - The local computer, when -ComputerName is not given. The computer named in the file name is never used, so a file exported from another computer can be copied here and imported, and nothing is changed remotely unless you ask.
          - The computers given with -ComputerName, so one baseline file can be applied to many computers.
          - The computer in each piped Export-WinClatConfiguration result, which carries Path and ComputerName, so a fleet can be restored from its own exports.
        A computer that would receive more than one file in a run is refused, and nothing is changed on it. Piping several files from Get-ChildItem without -ComputerName therefore changes nothing: they would all apply to the local computer.

        Only settings whose persistent (local) value differs from the file are written, so the confirmation names only real changes. Every computer returns one WinClat.SetResult per setting in the file: written settings report the values read back after the change, and settings that already matched report Success with the message that they were not written.

        As with Set-WinClatConfiguration, the current configuration is read first, a change that would leave both Pref64FromRA and Pref64FromDns disabled is refused, settings that Group Policy controls are written locally and reported as PolicyOverride when the policy keeps a different value, and the configuration is read back after every change. Changes do not ask for confirmation by default, except that when the run would disable AutoEnable or Permit on any computer, every computer in the run asks, because disabling either stops CLAT on every automatically enabled interface. Manual instance state is not part of an export and is not changed.

        Requires elevation on the target computer. Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

        The function does not write a log. Piping the results to Export-Csv keeps a complete record of a run.

    .PARAMETER Path
        One or more files written by Export-WinClatConfiguration. Accepts pipeline input by value, and by property name from Get-ChildItem (FullName) and from Export-WinClatConfiguration results (Path). Objects without a path, such as failed export rows, are skipped.

    .PARAMETER ComputerName
        The computers to apply the files to. When omitted, the files are applied to the local computer. Accepts pipeline input by property name from Export-WinClatConfiguration results.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Not used for the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections. The default is 32.

    .INPUTS
        System.String. File paths.

        System.IO.FileInfo. Files from Get-ChildItem.

        WinClat.ExportResult. Results from Export-WinClatConfiguration.

    .OUTPUTS
        WinClat.SetResult. When a run returns exactly one result, it also carries the type name WinClat.SetResult#Single, which selects a list view instead of the default table.

    .EXAMPLE
        Import-WinClatConfiguration -Path C:\WinClatTransfer\WinCLAT-CLIENT4-20261024-205512.txt

        Applies the configuration exported from CLIENT4 to the local computer.

    .EXAMPLE
        Get-ChildItem -Path C:\Exports\WinCLAT-CLIENT4-*.txt | Sort-Object -Property Name | Select-Object -Last 1 | Import-WinClatConfiguration -ComputerName CLIENT4

        Restores the most recent export of CLIENT4 to CLIENT4 over WinRM.

    .EXAMPLE
        Import-WinClatConfiguration -Path .\Baseline.txt -ComputerName (Get-Content -Path .\clients.txt) -WhatIf

        Shows which settings the baseline would change on each computer in clients.txt, without changing anything.

    .EXAMPLE
        $Exports = Get-Content -Path .\clients.txt | Export-WinClatConfiguration -Path C:\Exports
        $Exports | Import-WinClatConfiguration | Export-Csv -Path C:\Exports\Restore.csv -NoTypeInformation

        Exports every computer in clients.txt, and later restores each computer from its own export and records the results. Computers whose export failed are skipped.

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

        See docs/DESIGN.md, section 7.7.

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    [OutputType('WinClat.SetResult')]

    Param (

        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Path,

        # No Name alias: FileInfo objects from Get-ChildItem have a Name property, which would bind as a computer name.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]]$ComputerName,

        [PSCredential]$Credential,

        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit = 32

    )

    Begin {

        $Pairs = New-Object -TypeName 'System.Collections.Generic.List[object]'

        $WriteFailure = {

            Param ($Message, $ErrorId, $Category, $Target)

            $Exception = New-Object -TypeName System.InvalidOperationException -ArgumentList $Message
            $PSCmdlet.WriteError((New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $Exception, $ErrorId, $Category, $Target))

        }

    }

    Process {

        $Names = @($ComputerName | ForEach-Object -Process { "$_".Trim() } | Where-Object -FilterScript { $_ -and -not $_.StartsWith('#') })

        ForEach ($Item in @($Path | Where-Object -FilterScript { $_ })) {

            If (-not (Test-Path -LiteralPath $Item -PathType Leaf)) {

                & $WriteFailure "'$Item' is not an existing file, so it was not imported." 'WinClatImportFileNotFound' 'ObjectNotFound' $Item
                Continue

            }

            $File = (Resolve-Path -LiteralPath $Item).ProviderPath
            $Targets = $Names

            # Like every other command, the local computer unless -ComputerName names others. The computer in the file
            # name is never used, so a file is not applied remotely by surprise (DESIGN.md, section 7.7).
            If ($Targets.Count -eq 0) {

                $Targets = @($env:COMPUTERNAME)

            }

            ForEach ($Name in $Targets) {

                $Pairs.Add([PSCustomObject]@{ ComputerName = $Name; File = $File })

            }

        }

    }

    End {

        # Parse each file once. The content is checked, never run.
        $Parsed = @{}

        ForEach ($File in @($Pairs | ForEach-Object -Process { $_.File } | Sort-Object -Unique)) {

            Try {

                $Result = ConvertFrom-WinClatDump -InputObject @(Get-Content -LiteralPath $File -ErrorAction Stop)

            }

            Catch {

                $Result = [PSCustomObject]@{ Settings = @{}; Problem = "it could not be read: $($_.Exception.Message)" }

            }

            If ($Result.Problem) {

                & $WriteFailure "$([System.IO.Path]::GetFileName($File)): the file was refused because $($Result.Problem)" 'WinClatImportInvalidFile' 'InvalidData' $File

            }

            $Parsed[$File] = $Result

        }

        # One file per computer. A computer that would receive two different files is refused.
        $RequestByComputer = @{}
        $Source = @{}
        $Order = New-Object -TypeName 'System.Collections.Generic.List[string]'

        ForEach ($Group in @($Pairs | Group-Object -Property ComputerName)) {

            $Files = @($Group.Group | ForEach-Object -Process { $_.File } | Sort-Object -Unique)
            $Name = $Group.Group[0].ComputerName

            If ($Files.Count -gt 1) {

                & $WriteFailure "${Name}: more than one file would be imported ($((@($Files | ForEach-Object -Process { [System.IO.Path]::GetFileName($_) })) -join ', ')), so nothing was changed. Import one file per computer." 'WinClatImportConflict' 'InvalidOperation' $Name
                Continue

            }

            If ($Parsed[$Files[0]].Problem) {

                Continue

            }

            $RequestByComputer[$Name] = $Parsed[$Files[0]].Settings
            $Source[$Name] = [System.IO.Path]::GetFileName($Files[0])
            $Order.Add($Name)

        }

        If ($Order.Count -eq 0) {

            Return

        }

        $Shared = @{

            ThrottleLimit = $ThrottleLimit
            Cmdlet        = $PSCmdlet

        }

        If ($Credential) {

            $Shared['Credential'] = $Credential

        }

        # One summary warning at the end instead of an error per computer (DESIGN.md, section 4.6). For a single computer the
        # results are held, so exactly one is shown as a list and several as a table (section 6); fleet results still stream.
        $Tally = New-WinClatTally -ComputerName $Order.ToArray()

        # Pass 1: read and validate every computer, keeping only the settings that differ from the file.
        $Items = @(Get-WinClatConfigurationPlan @Shared -ComputerName $Order.ToArray() -RequestByComputer $RequestByComputer -OnlyChanged)

        # Disabling AutoEnable or Permit stops CLAT on every automatically enabled interface, so the run confirms like
        # ConfirmImpact High. The preference is read at the first ShouldProcess call, so it applies to every computer in the run.
        If (@($Items | Where-Object -FilterScript { $_.PSObject.TypeNames[0] -eq 'WinClat.ConfigurationPlan' -and ($_.DisablesAutoEnable -or $_.DisablesPermit) }).Count -gt 0 -and $ConfirmPreference -eq 'High') {

            $ConfirmPreference = 'Medium'

        }

        $Run = New-Object -TypeName 'System.Collections.Generic.List[object]'

        ForEach ($Item in $Items) {

            If ($Item.PSObject.TypeNames[0] -ne 'WinClat.ConfigurationPlan') {

                $Item | Measure-WinClatResult -Tally $Tally
                Continue

            }

            # Nothing differs, so there is nothing to confirm; the unchanged rows are still returned.
            If ($Item.Change.Count -eq 0 -or $PSCmdlet.ShouldProcess($Item.ComputerName, "$($Item.Action) Source: $($Source[$Item.ComputerName]).")) {

                $Run.Add($Item)

            }

        }

        # Pass 2: change the confirmed computers and verify by reading the configuration back.
        If ($Run.Count -gt 0) {

            Invoke-WinClatConfigurationChange @Shared -Plan $Run.ToArray() | Measure-WinClatResult -Tally $Tally

        }

        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'changed' -Cmdlet $PSCmdlet

    }

}
