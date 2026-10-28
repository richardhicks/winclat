Function Invoke-WinClatRemote {

    <#

    .SYNOPSIS
        Runs a WinCLAT script block locally or on remote computers and normalizes failures.

    .DESCRIPTION
        Shared execution helper for the public functions (DESIGN.md, sections 4.2 to 4.6):
          - Trims target names, skips blank values and values beginning with '#', and removes duplicates (case-insensitive, first spelling wins).
          - Runs locally without WinRM when the target is '.', 'localhost', '127.0.0.1', '::1', or the local computer name or FQDN. Local runs use a separate runspace in the same process, so the script block must be self-contained there too, and its errors, warnings, and verbose messages are forwarded.
          - Checks TCP 5985 on every remote target at once with Test-WinClatWsManPort. A target that does not answer within two seconds, or whose name does not resolve, is returned as Unreachable with a short message and is not passed to Invoke-Command.
          - Otherwise runs a single Invoke-Command against all remote targets with Credential and ThrottleLimit.
          - Sets ComputerName on every returned object to the name as supplied, removes the PSComputerName, PSShowComputerName, and RunspaceId properties added by remoting, and restores WinClat.* type names lost to deserialization.
          - Converts remoting failures captured with -ErrorVariable into failure objects with Status 'Unreachable', built by the caller's NewFailureObject script block.
          - Guarantees at least one object per target: a target that returns nothing produces a 'Failed' object.
          - Writes no error for a target that has a result row: its Status and Message carry the outcome, and the public function writes one summary warning (DESIGN.md, section 4.6). Error records from a target are written to the verbose stream instead. An error that cannot be attributed to any target is still written as an error, through the caller's $PSCmdlet.
          - Sends the caller's verbose preference with the script block, because over WinRM only the target's preference decides whether verbose records are displayed. When verbose output is requested, the networking modules are imported quietly first, so their exported function list is not shown.

        The script block passed in must be self-contained, including any private helper definitions it needs.

    .PARAMETER ComputerName
        The target computers. Blank values, comment values beginning with '#', and duplicates are ignored.

    .PARAMETER ScriptBlock
        The self-contained script block to run on each target.

    .PARAMETER ArgumentList
        Arguments passed positionally to the script block.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Ignored, with a warning, for targets that resolve to the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections.

    .PARAMETER NewFailureObject
        Script block that builds a failure object of the caller's output type. It receives three positional arguments: the computer name as supplied, the Status value, and the message. This keeps failure rows in the same shape as success rows for Export-Csv.

    .PARAMETER Cmdlet
        The $PSCmdlet of the public function. Verbose messages, and errors that cannot be attributed to a target, are written through it, so they are attributed to that function and the caller's command line (DESIGN.md, section 4.6). When omitted, they are written through this function.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject. The objects returned by the script block, plus one failure object for each target that could not be reached or returned nothing.

    .EXAMPLE
        Invoke-WinClatRemote -ComputerName 'CLIENT1', 'CLIENT2' -ScriptBlock $RemoteScript -NewFailureObject $NewFailure -ThrottleLimit 16 -Cmdlet $PSCmdlet

        Runs $RemoteScript on CLIENT1 and CLIENT2 in parallel and returns one or more objects per computer.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/invoke-command

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
    [OutputType([PSCustomObject])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @(),

        [PSCredential]$Credential,

        [int]$ThrottleLimit = 32,

        [Parameter(Mandatory)]
        [scriptblock]$NewFailureObject,

        [System.Management.Automation.PSCmdlet]$Cmdlet

    )

    If (-not $Cmdlet) {

        $Cmdlet = $PSCmdlet

    }

    # A target's error records go to the verbose stream, because its result row carries the outcome (DESIGN.md, section 4.6).
    $WriteDetail = {

        Param ($Name, $ErrorRecord)

        $Cmdlet.WriteVerbose("${Name}: $($ErrorRecord.Exception.Message)")

    }

    # Over WinRM the target's $VerbosePreference alone decides whether verbose records are shown, and the caller's
    # -Verbose does not reach it, so the caller's effective preference is set on the target (DESIGN.md, section 4.3).
    # $VerbosePreference here resolves to the public function's value, which -Verbose sets to Continue.
    $Preamble = "`$VerbosePreference = 'SilentlyContinue'`n"

    If ($VerbosePreference -ne 'SilentlyContinue' -and $VerbosePreference -ne 'Ignore') {

        # Loading these modules while the preference is Continue lists every function they export, even with
        # Import-Module -Verbose:$false, so they are imported before the preference is raised.
        $Preamble += "Import-Module -Name NetAdapter, NetTCPIP, DnsClient -ErrorAction SilentlyContinue`n`$VerbosePreference = 'Continue'`n"

    }

    $ScriptBlock = [scriptblock]::Create("$Preamble& {`n$($ScriptBlock.ToString())`n} @args`n")

    # Names that refer to this computer and run in-process without WinRM.
    $LocalNames = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $IPGlobal = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()

    ForEach ($Name in @('.', 'localhost', '127.0.0.1', '::1', $env:COMPUTERNAME, $IPGlobal.HostName)) {

        If ($Name) {

            [void]$LocalNames.Add($Name)

        }

    }

    If ($IPGlobal.DomainName) {

        [void]$LocalNames.Add("$($IPGlobal.HostName).$($IPGlobal.DomainName)")

    }

    # Trim, skip blanks and comments, and remove duplicates while keeping the first spelling.
    $Seen = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $LocalTargets = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $RemoteTargets = New-Object -TypeName 'System.Collections.Generic.List[string]'

    ForEach ($Name in $ComputerName) {

        If ($null -eq $Name) {

            Continue

        }

        $Name = $Name.Trim()

        If ($Name -eq '' -or $Name.StartsWith('#') -or -not $Seen.Add($Name)) {

            Continue

        }

        If ($LocalNames.Contains($Name)) {

            $LocalTargets.Add($Name)

        }

        Else {

            $RemoteTargets.Add($Name)

        }

    }

    # Supplied spelling of each remote target, keyed case-insensitively, and the number of objects each returned.
    $SuppliedName = @{}
    $ResultCount = @{}

    ForEach ($Name in $RemoteTargets) {

        $SuppliedName[$Name] = $Name
        $ResultCount[$Name] = 0

    }

    $RemotingProperties = @('PSComputerName', 'PSShowComputerName', 'RunspaceId')

    # Run local targets in-process, in a separate runspace. The script block is self-contained, as it is remotely, and
    # a terminating error inside it is returned as an error record instead of being thrown into this scope, which would
    # add duplicate entries to the caller's -ErrorVariable.
    $LocalScript = "Try {`n& {`n$($ScriptBlock.ToString())`n} @args`n}`nCatch {`nWrite-Error -ErrorRecord `$_`n}"

    ForEach ($Name in $LocalTargets) {

        If ($Credential) {

            Write-Warning -Message "$Name is the local computer. It runs in the current session and the supplied credential is not used."

        }

        $Output = @()
        $LocalErrors = @()
        $PowerShell = [PowerShell]::Create()

        Try {

            [void]$PowerShell.AddScript($LocalScript)

            ForEach ($Argument in $ArgumentList) {

                [void]$PowerShell.AddArgument($Argument)

            }

            $Output = @($PowerShell.Invoke())

            ForEach ($Record in $PowerShell.Streams.Verbose) {

                Write-Verbose -Message $Record.Message

            }

            ForEach ($Record in $PowerShell.Streams.Warning) {

                Write-Warning -Message $Record.Message

            }

            $LocalErrors = @($PowerShell.Streams.Error)

        }

        Catch {

            $LocalErrors = @($_)

        }

        Finally {

            $PowerShell.Dispose()

        }

        ForEach ($Result in $Output) {

            $Result = Complete-WinClatRemoteResult -InputObject $Result -ComputerName $Name -RemoveProperty $RemotingProperties
            $Result

        }

        ForEach ($ErrorRecord in $LocalErrors) {

            & $WriteDetail $Name $ErrorRecord

        }

        If ($Output.Count -eq 0) {

            If ($LocalErrors.Count -gt 0) {

                & $NewFailureObject $Name 'Failed' $LocalErrors[0].Exception.Message

            }

            Else {

                & $NewFailureObject $Name 'Failed' 'No result was returned.'

            }

        }

    }

    If ($RemoteTargets.Count -eq 0) {

        Return

    }

    # Check the WinRM port of every remote target at once, so an offline computer is reported in about two seconds
    # instead of after a WinRM connection timeout (DESIGN.md, section 4.3).
    $PortFailures = Test-WinClatWsManPort -ComputerName $RemoteTargets.ToArray()

    ForEach ($Name in @($RemoteTargets | Where-Object -FilterScript { $PortFailures.ContainsKey($_) })) {

        & $NewFailureObject $Name 'Unreachable' $PortFailures[$Name]
        [void]$RemoteTargets.Remove($Name)

    }

    If ($RemoteTargets.Count -eq 0) {

        Return

    }

    $InvokeParameters = @{

        ComputerName  = $RemoteTargets.ToArray()
        ScriptBlock   = $ScriptBlock
        ArgumentList  = $ArgumentList
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'RemoteErrors'

    }

    If ($Credential) {

        $InvokeParameters['Credential'] = $Credential

    }

    $RemoteErrors = $null

    Invoke-Command @InvokeParameters | ForEach-Object -Process {

        $Name = [string]$_.PSComputerName

        If ($SuppliedName.ContainsKey($Name)) {

            $Name = $SuppliedName[$Name]
            $ResultCount[$Name]++

        }

        $Result = Complete-WinClatRemoteResult -InputObject $_ -ComputerName $Name -RemoveProperty $RemotingProperties
        $Result

    }

    # Errors raised by the script block on a target carry OriginInfo; connection failures do not.
    $ConnectionError = @{}
    $ScriptError = @{}

    ForEach ($ErrorRecord in @($RemoteErrors)) {

        If ($null -eq $ErrorRecord) {

            Continue

        }

        $Name = $null

        If ($ErrorRecord -is [System.Management.Automation.Runspaces.RemotingErrorRecord] -and $ErrorRecord.OriginInfo) {

            $Name = [string]$ErrorRecord.OriginInfo.PSComputerName

            If ($SuppliedName.ContainsKey($Name) -and -not $ScriptError.ContainsKey($SuppliedName[$Name])) {

                $ScriptError[$SuppliedName[$Name]] = $ErrorRecord

            }

        }

        Else {

            ForEach ($Candidate in @($ErrorRecord.TargetObject, $ErrorRecord.CategoryInfo.TargetName)) {

                If ($Candidate -is [string] -and $SuppliedName.ContainsKey($Candidate)) {

                    $Name = $SuppliedName[$Candidate]
                    Break

                }

            }

            If ($Name -and -not $ConnectionError.ContainsKey($Name)) {

                $ConnectionError[$Name] = $ErrorRecord

            }

        }

        # An error that belongs to no target has no row to carry it, so it stays an error.
        If ($Name) {

            & $WriteDetail $Name $ErrorRecord

        }

        Else {

            $Cmdlet.WriteError($ErrorRecord)

        }

    }

    # Every remote target produces at least one object.
    ForEach ($Name in $RemoteTargets) {

        If ($ResultCount[$Name] -gt 0) {

            Continue

        }

        If ($ConnectionError.ContainsKey($Name)) {

            & $NewFailureObject $Name 'Unreachable' $ConnectionError[$Name].Exception.Message

        }

        ElseIf ($ScriptError.ContainsKey($Name)) {

            & $NewFailureObject $Name 'Failed' $ScriptError[$Name].Exception.Message

        }

        Else {

            & $NewFailureObject $Name 'Failed' 'No result was returned.'

        }

    }

}
