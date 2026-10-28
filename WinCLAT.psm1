#Requires -Version 5.1

# Load private helpers first, then public functions. Each file contains one function.
$Private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$Public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

ForEach ($File in @($Private + $Public)) {

    Try {

        . $File.FullName

    }

    Catch {

        Write-Error -Message "Failed to import function $($File.FullName): $_"

    }

}

# NOTE: Private helpers are not available inside a remote Invoke-Command session.
# The remote script block must carry their definitions with it. See docs/DESIGN.md, section 4.3.

Export-ModuleMember -Function $Public.BaseName
