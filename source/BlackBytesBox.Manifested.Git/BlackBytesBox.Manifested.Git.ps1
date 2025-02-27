function Get-GitTopLevelDirectory {
    <#
    .SYNOPSIS
        Retrieves the top-level directory of the current Git repository.

    .DESCRIPTION
        This function calls Git using 'git rev-parse --show-toplevel' to determine
        the root directory of the current Git repository. If Git is not available
        or the current directory is not within a Git repository, the function returns
        an error. The function converts any forward slashes to the system's directory
        separator (works correctly on both Windows and Linux).

    .PARAMETER None
        This function does not require any parameters.

    .EXAMPLE
        PS C:\Projects\MyRepo> Get-GitTopLevelDirectory
        C:\Projects\MyRepo

    .NOTES
        Ensure Git is installed and available in your system's PATH.
    #>
    [CmdletBinding()]
    [alias("ggtd")]
    param()

    try {
        # Attempt to retrieve the top-level directory of the Git repository.
        $topLevel = git rev-parse --show-toplevel 2>$null

        if (-not $topLevel) {
            Write-Error "Not a Git repository or Git is not available in the PATH."
            return $null
        }

        # Trim the result and replace forward slashes with the current directory separator.
        $topLevel = $topLevel.Trim().Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        return $topLevel
    }
    catch {
        Write-Error "Error retrieving Git top-level directory: $_"
    }
}

function Get-GitCurrentBranch {
    <#
    .SYNOPSIS
    Retrieves the current Git branch name.

    .DESCRIPTION
    This function calls Git to determine the current branch. It first uses
    'git rev-parse --abbrev-ref HEAD' to get the branch name. If the output is
    "HEAD" (indicating a detached HEAD state), it then attempts to find a branch
    that contains the current commit using 'git branch --contains HEAD'. If no
    branch is found, it falls back to returning the commit hash.

    .EXAMPLE
    PS C:\> Get-GitCurrentBranch

    Returns:
    master

    .NOTES
    - Ensure Git is available in your system's PATH.
    - In cases of a detached HEAD with multiple containing branches, the first
      branch found is returned.
    #>
    [CmdletBinding()]
    [alias("ggtd")]
    param()
    
    try {
        # Get the abbreviated branch name
        $branch = git rev-parse --abbrev-ref HEAD 2>$null

        # If HEAD is returned, we're in a detached state.
        if ($branch -eq 'HEAD') {
            # Try to get branch names that contain the current commit.
            $branches = git branch --contains HEAD 2>$null | ForEach-Object {
                # Remove any asterisks or leading/trailing whitespace.
                $_.Replace('*','').Trim()
            } | Where-Object { $_ -ne '' }

            if ($branches.Count -gt 0) {
                # Return the first branch found
                return $branches[0]
            }
            else {
                # As a fallback, return the commit hash.
                return git rev-parse HEAD 2>$null
            }
        }
        else {
            return $branch.Trim()
        }
    }
    catch {
        Write-Error "Error retrieving Git branch: $_"
    }
}

function Get-GitRepositoryName {
    <#
    .SYNOPSIS
        Gibt den Namen des Git-Repositories anhand der Remote-URL zurück.

    .DESCRIPTION
        Diese Funktion ruft über 'git config --get remote.origin.url' die Remote-URL des Repositories ab.
        Anschließend wird der Repository-Name aus der URL extrahiert, indem der letzte Teil der URL (nach dem letzten "/" oder ":")
        entnommen und eine eventuell vorhandene ".git"-Endung entfernt wird.
        Sollte keine Remote-URL vorhanden sein, wird ein Fehler ausgegeben.

    .PARAMETER None
        Diese Funktion benötigt keine Parameter.

    .EXAMPLE
        PS C:\Projects\MyRepo> Get-GitRepositoryName
        MyRepo

    .NOTES
        Stelle sicher, dass Git installiert ist und in deinem Systempfad verfügbar ist.
    #>
    [CmdletBinding()]
    [alias("ggrn")]
    param()

    try {
        # Remote-URL des Repositories abrufen
        $remoteUrl = git config --get remote.origin.url 2>$null

        if (-not $remoteUrl) {
            Write-Error "Keine Remote-URL gefunden. Stelle sicher, dass das Repository eine Remote-URL besitzt."
            return $null
        }

        $remoteUrl = $remoteUrl.Trim()

        # Entferne eine eventuell vorhandene ".git"-Endung
        if ($remoteUrl -match "\.git$") {
            $remoteUrl = $remoteUrl.Substring(0, $remoteUrl.Length - 4)
        }

        # Unterscheidung zwischen URL-Formaten (HTTPS/SSH)
        if ($remoteUrl.Contains('/')) {
            $parts = $remoteUrl.Split('/')
        }
        else {
            # SSH-Format: z.B. git@github.com:User/Repo
            $parts = $remoteUrl.Split(':')
        }

        # Letztes Element als Repository-Name extrahieren
        $repoName = $parts[-1]
        return $repoName
    }
    catch {
        Write-Error "Fehler beim Abrufen des Repository-Namens: $_"
    }
}

