Function Get-WinClatConfiguration {

    <#

    .SYNOPSIS
        Returns global Windows CLAT (WinCLAT) configuration.

    .DESCRIPTION
        Wraps 'netsh.exe interface clat show global' and returns the output as WinClat.Configuration objects. Runs locally or against one or more remote computers in parallel. Does not require elevation.

        Every computer produces at least one object. Computers that cannot be reached return Status Unreachable, computers without the WinCLAT feature return Status FeatureNotAvailable with their OS build, and Windows Server computers without it return Status NotSupported, because Microsoft delivers WinCLAT to client editions only. WinCLAT is generally available on Windows 11 version 25H2 build 26200.9550 and later.

        PolicyControlled lists the settings that Group Policy controls, as a comma-separated string such as 'Permit, Pref64FromRA'. CollectedAtUtc records when netsh ran on the target, in UTC.

        Remote computers must have WinRM enabled, typically through Group Policy. Roaming devices may be offline at run time. Each remote computer is first checked on TCP 5985 (WinRM over HTTP); one that does not answer within 2 seconds, or whose name does not resolve, is returned as Unreachable at once instead of after a WinRM timeout. Failures are not written as errors: every computer returns its result with a Status and a Message that explains it, and when a run for several computers has any computer that did not complete, one warning at the end gives the count. To list them, filter the results, for example with Where-Object -FilterScript { $_.Status -ne 'Success' }.

    .PARAMETER Store
        Configuration store to return. Active is the effective configuration, Persistent is the local configuration (which Group Policy may override), and Both returns one object for each.

    .PARAMETER ComputerName
        One or more computers to query. Accepts pipeline input by value and by property name, including objects from Get-ADComputer and Get-ADObject; DNSHostName is preferred over Name. Blank values and values beginning with '#' are ignored, so Get-Content output can be piped directly. Defaults to the local computer.

    .PARAMETER Credential
        Credentials used to connect to remote computers. Not used for the local computer.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent remote connections. The default is 32.

    .INPUTS
        System.String. Computer names.

        System.Management.Automation.PSObject. Objects with a DNSHostName, ComputerName, Name, or CN property, such as those from Get-ADComputer and Get-ADObject.

    .OUTPUTS
        WinClat.Configuration. When a run returns exactly one result, it also carries the type name WinClat.Configuration#Single, which selects a list view instead of the default table.

    .EXAMPLE
        Get-WinClatConfiguration -Store Both

        Returns the active and persistent configuration of the local computer.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Get-WinClatConfiguration

        Returns the active configuration of each computer listed in clients.txt.

    .EXAMPLE
        Get-ADComputer -Filter * -SearchBase 'OU=Windows Clients,DC=lab,DC=richardhicks,DC=net' | Get-WinClatConfiguration | Export-Csv -Path .\winclat.csv -NoTypeInformation

        Exports the active configuration of every computer in the OU to a CSV file.

    .EXAMPLE
        Get-Content -Path .\clients.txt | Get-WinClatConfiguration | Where-Object -FilterScript { $_.Status -ne 'Unreachable' }

        Returns the configuration of the computers in clients.txt that could be reached, leaving out the Unreachable rows. The warning at the end still counts the computers that were unreachable.

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

        See docs/DESIGN.md, section 7.1.

    #>

    [CmdletBinding(PositionalBinding = $false)]
    [OutputType('WinClat.Configuration')]

    Param (

        [ValidateSet('Active', 'Persistent', 'Both')]
        [string]$Store = 'Active',
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
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

        $NewFailure = {

            Param ($Name, $Status, $Message)

            ConvertTo-WinClatConfiguration -ComputerName $Name -Status $Status -Message $Message -CollectedAtUtc (Get-Date).ToUniversalTime()

        }

        $RemoteParameters = @{

            ComputerName     = $Targets.ToArray()
            ScriptBlock      = Get-WinClatConfigurationScript
            ArgumentList     = @($Store.ToLowerInvariant())
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

        Invoke-WinClatRemote @RemoteParameters | Measure-WinClatResult -Tally $Tally
        Complete-WinClatResult -Tally $Tally

        Write-WinClatFailureSummary -Tally $Tally -Action 'queried' -Cmdlet $PSCmdlet

    }

}
