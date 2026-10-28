Function Export-WinClatConfiguration {

    <#

    .SYNOPSIS
        Saves Windows CLAT (WinCLAT) configuration as a replayable netsh script.

    .DESCRIPTION
        Wraps 'netsh.exe interface clat dump'. Runs locally or against one or more remote computers in parallel, writes one file per computer to the folder given by -Path on the calling computer, and returns one WinClat.ExportResult object per computer, including computers that failed. Does not require elevation on the target computer.

        Each file is named WinCLAT-<ComputerName>-<yyyyMMdd-HHmmss>.txt, using the computer name as supplied and one UTC timestamp for the whole run, so repeated runs keep a history of baselines. Existing files are never overwritten. The file holds the netsh output exactly as returned: a single 'set global' line inside 'pushd interface clat' and 'popd'. Replay it on the computer with 'netsh.exe -f <file>' from an elevated prompt.

        dump exports the persistent (local) values, not values set by Group Policy, so replaying a file restores the local configuration while any policy keeps applying on top of it. PolicyControlled on the result lists the settings that Group Policy controls at export time. Manual instance state is not exported, because it is not persistent.

        The result also carries the Permit, Pref64FromDns, Pref64FromRA, and AutoEnable values read from the file, so the results can be compared or exported with Export-Csv.

        -WhatIf reads every computer and lists the files that would be written, without writing them.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

    .PARAMETER Path
        An existing folder on the calling computer where the export files are written.

    .PARAMETER ComputerName
        One or more computers to export. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Not used for the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections. The default is 32.

    .INPUTS
        System.String. Computer names.

        System.Management.Automation.PSObject. Objects with a DNSHostName, ComputerName, Name, or CN property, such as those from Get-ADComputer and Get-ADObject.

    .OUTPUTS
        WinClat.ExportResult. When a run returns exactly one result, it also carries the type name WinClat.ExportResult#Single, which selects a list view instead of the default table.

    .EXAMPLE
        Export-WinClatConfiguration -ComputerName CLIENT4 -Path C:\Exports

        Saves the WinCLAT configuration of CLIENT4 to a file such as C:\Exports\WinCLAT-CLIENT4-20261022-183146.txt.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Export-WinClatConfiguration -Path C:\Exports | Export-Csv -Path C:\Exports\Index.csv -NoTypeInformation -Append

        Exports every computer in clients.txt and appends one row per computer, including Unreachable and Failed rows, to an index of the exports.

    .EXAMPLE
        netsh.exe -f C:\Exports\WinCLAT-CLIENT4-20261022-183146.txt

        Run on CLIENT4 from an elevated prompt, restores the exported local configuration.

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

        See docs/DESIGN.md, section 7.5.

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', PositionalBinding = $false)]
    [OutputType('WinClat.ExportResult')]

    Param (

        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({

                If (-not (Test-Path -LiteralPath $_ -PathType Container) -or (Get-Item -LiteralPath $_).PSProvider.Name -ne 'FileSystem') {

                    Throw "'$_' is not an existing folder. Create the folder first."

                }

                $true

            })]
        [string]$Path,
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DNSHostName', 'CN', 'Name')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [PSCredential]$Credential,

        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit = 32

    )

    Begin {

        $Targets = New-Object -TypeName 'System.Collections.Generic.List[string]'

    }

    Process {

        # Read $_ only for pipeline input; otherwise it may be an outer ForEach-Object variable.
        $PipelineObject = $null

        If ($MyInvocation.ExpectingInput) {

            $PipelineObject = $_

        }

        ForEach ($Name in @(Get-WinClatTargetName -InputObject $PipelineObject -ComputerName $ComputerName -Cmdlet $PSCmdlet)) {

            $Targets.Add($Name)

        }

    }

    End {

        $Folder = (Resolve-Path -LiteralPath $Path).ProviderPath

        # One timestamp for the whole run, so the files of one fleet export sort together.
        $Stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
        $InvalidCharacters = [regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())

        $NewFailure = {

            Param ($Name, $Status, $Message)

            ConvertTo-WinClatExportResult -ComputerName $Name -Status $Status -Message $Message -CollectedAtUtc (Get-Date).ToUniversalTime()

        }

        $RemoteParameters = @{

            ComputerName     = $Targets.ToArray()
            ScriptBlock      = Get-WinClatExportScript
            ThrottleLimit    = $ThrottleLimit
            NewFailureObject = $NewFailure
            Cmdlet           = $PSCmdlet

        }

        If ($Credential) {

            $RemoteParameters['Credential'] = $Credential

        }

        # One summary warning at the end instead of an error per computer (DESIGN.md, section 4.6). For a single computer the
        # results are held, so exactly one is shown as a list and several as a table (section 6); fleet results still stream.
        $Tally = New-WinClatTally -ComputerName $Targets.ToArray()

        ForEach ($Row in @(Invoke-WinClatRemote @RemoteParameters)) {

            # Failures arrive as WinClat.ExportResult rows, and their errors are already written.
            If ($Row.PSObject.TypeNames[0] -ne 'WinClat.ExportData') {

                $Row | Measure-WinClatResult -Tally $Tally
                Continue

            }

            # Computer names such as IPv6 literals can contain characters that are not valid in a file name.
            $SafeName = [regex]::Replace($Row.ComputerName, "[$InvalidCharacters]", '_')
            $File = Join-Path -Path $Folder -ChildPath "WinCLAT-$SafeName-$Stamp.txt"

            $Result = @{

                ComputerName     = $Row.ComputerName
                Settings         = @{ Permit = $Row.Permit; Pref64FromDns = $Row.Pref64FromDns; Pref64FromRA = $Row.Pref64FromRA; AutoEnable = $Row.AutoEnable }
                PolicyControlled = $Row.PolicyControlled
                CollectedAtUtc   = $Row.CollectedAtUtc

            }

            If (-not $PSCmdlet.ShouldProcess($File, "Save the WinCLAT configuration of $($Row.ComputerName)")) {

                Continue

            }

            # The Failed row carries the reason; no error is written (DESIGN.md, section 4.6).
            $WriteFailure = {

                Param ($Message)

                ConvertTo-WinClatExportResult @Result -Status 'Failed' -Message $Message | Measure-WinClatResult -Tally $Tally

            }

            # Checked first because a caught exception also lands in the caller's -ErrorVariable.
            If ([System.IO.File]::Exists($File)) {

                & $WriteFailure "The export file could not be written: '$File' already exists, and existing files are never overwritten."
                Continue

            }

            Try {

                # CreateNew never overwrites an existing file. ASCII is what netsh -f expects.
                $Bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$Row.Content)
                $Stream = [System.IO.File]::Open($File, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)

                Try {

                    $Stream.Write($Bytes, 0, $Bytes.Length)

                }

                Finally {

                    $Stream.Dispose()

                }

            }

            Catch {

                # .NET method calls wrap the IOException in a MethodInvocationException.
                $Inner = $_.Exception

                If ($Inner.InnerException) {

                    $Inner = $Inner.InnerException

                }

                & $WriteFailure "The export file could not be written: $($Inner.Message)"
                Continue

            }

            ConvertTo-WinClatExportResult @Result -Status 'Success' -Path $File | Measure-WinClatResult -Tally $Tally

        }

        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'queried' -Cmdlet $PSCmdlet

    }

}
