Function ConvertFrom-WinClatNetshOutput {

    <#

    .SYNOPSIS
        Parses 'netsh interface clat show' output into objects.

    .DESCRIPTION
        Converts the output of 'netsh.exe interface clat show global' and 'netsh.exe interface clat show instance' into one object per block of key/value lines.

        Parser rules (DESIGN.md, section 5.3):
          1. Skip dash-only lines and leading blank lines.
          2. Match key/value lines with '^(?<Key>.+?)\s+:\s(?<Value>.*)$'. The separator is whitespace, colon, space, so IPv6 values parse correctly.
          3. A blank line, or the end of output, emits the current block as an object (handles store=both).
          4. Map known labels to property names (section 5.4); convert unknown labels generically.
          5. Convert enabled/disabled and yes/no to [bool], none to $null, lifetimes to [TimeSpan]. A remote prefix of ::/0, which netsh prints for an enabled instance that has not discovered a prefix, is also $null, because a NAT64 prefix is never shorter than /32 (RFC 6052).

        Lines that are not key/value pairs, such as netsh error messages, are written to the verbose stream and ignored. Output that contains no key/value lines produces no objects; the caller classifies failures from the exit code.

        A lifetime that cannot be parsed is returned as $null, and the raw string is added in a property with the same name plus a 'Raw' suffix (for example RemotePrefixRemainingLifetimeRaw).

        This function and ConvertTo-WinClatTimeSpan must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InputObject
        The lines of netsh output to parse. Strings that contain embedded line breaks are split into separate lines.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject. One object per block of key/value lines.

    .EXAMPLE
        ConvertFrom-WinClatNetshOutput -InputObject (netsh.exe interface clat show global store=both)

        Returns two objects, one with Store set to Active and one with Store set to Persistent.

    .EXAMPLE
        ConvertFrom-WinClatNetshOutput -InputObject (netsh.exe interface clat show instance interface=10)

        Returns one object with Enabled, IsTranslating, LocalPrefix, RemotePrefix, RemotePrefixRemainingLifetime, IPv6Address, and IPv4Address properties.

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

    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$InputObject

    )

    # Known netsh labels and their property names (DESIGN.md, section 5.4). Lookups are case-insensitive.
    $KnownLabels = @{

        'permit'                           = 'Permit'
        'pref64fromdns'                    = 'Pref64FromDns'
        'pref64fromra'                     = 'Pref64FromRA'
        'autoenable'                       = 'AutoEnable'
        'store'                            = 'Store'
        'State'                            = 'Enabled'
        'Is translating'                   = 'IsTranslating'
        'Local prefix'                     = 'LocalPrefix'
        'Remote prefix'                    = 'RemotePrefix'
        'Remote prefix remaining lifetime' = 'RemotePrefixRemainingLifetime'
        'IPv6 address'                     = 'IPv6Address'
        'IPv4 address'                     = 'IPv4Address'

    }

    $Lines = @($InputObject | ForEach-Object -Process { $_ -split '\r?\n' })

    # A trailing blank line guarantees the last block is emitted at the end of output.
    $Lines += ''

    $Properties = [ordered]@{}

    ForEach ($Line in $Lines) {

        $Line = $Line.TrimEnd()

        If ($Line -eq '') {

            If ($Properties.Count -gt 0) {

                [PSCustomObject]$Properties
                $Properties = [ordered]@{}

            }

            Continue

        }

        If ($Line -match '^-+$') {

            Continue

        }

        $Match = [regex]::Match($Line, '^(?<Key>.+?)\s+:\s(?<Value>.*)$')

        If (-not $Match.Success) {

            Write-Verbose -Message "Ignoring netsh output line: $Line"
            Continue

        }

        $Key = $Match.Groups['Key'].Value.Trim()
        $Value = $Match.Groups['Value'].Value.Trim()

        If ($KnownLabels.ContainsKey($Key)) {

            $Name = $KnownLabels[$Key]

        }

        Else {

            # Unknown label: split on spaces, capitalize each word, drop characters not valid in a simple property name.
            $Words = $Key -split '\s+' | Where-Object -FilterScript { $_ } | ForEach-Object -Process { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }
            $Name = ($Words -join '') -replace '[^A-Za-z0-9]', ''

        }

        # netsh prints none, or ::/0 for an enabled instance without a discovered prefix; both mean no value.
        If ($Value -eq 'none' -or ($Name -eq 'RemotePrefix' -and $Value -eq '::/0')) {

            $Properties[$Name] = $null

        }

        ElseIf ($Name -like '*Lifetime') {

            $Properties[$Name] = ConvertTo-WinClatTimeSpan -Value $Value

            If ($null -eq $Properties[$Name]) {

                $Properties["${Name}Raw"] = $Value

            }

        }

        ElseIf ($Value -in 'enabled', 'yes') {

            $Properties[$Name] = $true

        }

        ElseIf ($Value -in 'disabled', 'no') {

            $Properties[$Name] = $false

        }

        ElseIf ($Name -eq 'Store' -and $Value.Length -gt 0) {

            # netsh prints 'active' and 'persistent'; the property uses Active and Persistent.
            $Properties[$Name] = $Value.Substring(0, 1).ToUpper() + $Value.Substring(1).ToLower()

        }

        Else {

            $Properties[$Name] = $Value

        }

    }

}
