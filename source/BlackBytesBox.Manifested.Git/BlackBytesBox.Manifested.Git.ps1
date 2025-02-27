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

function Get-RemoteCommitId {
    <#
    .SYNOPSIS
    Retrieves the commit ID of a remote branch from a Git repository.

    .DESCRIPTION
    This function queries the remote Git repository using 'git ls-remote' to obtain the current commit ID
    of the specified branch directly from the remote, bypassing any potentially outdated local references.

    .PARAMETER BranchName
    Specifies the name of the remote branch to query (e.g., 'main', 'develop').

    .EXAMPLE
    PS C:\> Get-RemoteCommitId -BranchName "main"
    
    Retrieves and outputs the commit ID of the 'main' branch from the remote repository.

    .NOTES
    Ensure that Git is installed and available in the system's PATH.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    # Query the remote repository for the branch reference.
    # The output is in the form: <commitId><tab>refs/heads/<BranchName>
    $remoteOutput = git ls-remote origin "refs/heads/$BranchName"

    # Split the output by tab and take the first element (the commit ID)
    $commitId = $remoteOutput -split "`t" | Select-Object -First 1

    # Output the commit ID
    Write-Output $commitId
}


function Get-SafeDirectoryNameFromUrl {
    <#
    .SYNOPSIS
    Extracts and sanitizes the repository name from a Git repository URL.

    .DESCRIPTION
    This function takes a repository URL, extracts the base name (ignoring any trailing ".git"), 
    and replaces any invalid directory name characters with an underscore.

    .PARAMETER RepositoryUrl
    The URL of the repository.

    .EXAMPLE
    Get-SafeDirectoryNameFromUrl -RepositoryUrl "https://github.com/example/repo.git"
    Returns: "repo"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl
    )

    # Remove trailing "/" and ".git" (if present).
    $trimmedUrl = $RepositoryUrl.TrimEnd("/").Replace(".git", "")
    $baseName = [System.IO.Path]::GetFileName($trimmedUrl)

    # Define the set of invalid file name characters.
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        $baseName = $baseName -replace [regex]::Escape($char), "_"
    }
    return $baseName
}

function Mirror-DirectorySnapshot {
    <#
    .SYNOPSIS
    Mirrors the content of a source directory to a destination directory using native PowerShell commands.

    .DESCRIPTION
    This function synchronizes the destination directory with the source directory.
    It will:
      - Remove any files or directories in the destination that do not exist in the source.
      - Copy new or updated files and directories from the source to the destination.
    This effectively mirrors the source directory into the destination without using Robocopy.
    The function includes simple retry logic for file copy operations in case target files are in use.

    .PARAMETER Source
    The source directory path.

    .PARAMETER Destination
    The destination directory path.

    .PARAMETER RetryCount
    The number of times to retry a failed file copy operation. Defaults to 3.

    .PARAMETER RetryDelay
    The delay in milliseconds between retry attempts. Defaults to 2000 (2 seconds).

    .EXAMPLE
    Mirror-DirectorySnapshot -Source "C:\Temp\Snapshot" -Destination "C:\MyProject\repo" -RetryCount 5 -RetryDelay 3000
    Mirrors the snapshot directory to the specified destination with up to 5 retries and a 3000-millisecond delay between retries.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [int]$RetryCount = 10,

        [Parameter(Mandatory = $false)]
        [int]$RetryDelay = 6000
    )

    Write-Host "Synchronizing target directory '$Destination' with the snapshot..."

    # Ensure destination exists.
    if (-not (Test-Path -Path $Destination)) {
        try {
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Error "Failed to create destination folder '$Destination': $_"
            return
        }
    }

    # Get relative paths for items in source and destination.
    $sourceItems = Get-ChildItem -Path $Source -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($Source.Length).TrimStart('\')
    }
    $destinationItems = Get-ChildItem -Path $Destination -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($Destination.Length).TrimStart('\')
    }

    # Remove items from destination that do not exist in source.
    foreach ($destRelative in $destinationItems) {
        if ($sourceItems -notcontains $destRelative) {
            $destFullPath = Join-Path -Path $Destination -ChildPath $destRelative
            try {
                Remove-Item -Path $destFullPath -Recurse -Force -ErrorAction Stop
                Write-Host "Removed extra item: $destFullPath"
            }
            catch {
                Write-Warning "Failed to remove extra item '$destFullPath': $_"
            }
        }
    }

    # Copy or update files and directories from source to destination.
    $sourceEntries = Get-ChildItem -Path $Source -Recurse -Force
    foreach ($item in $sourceEntries) {
        $relativePath = $item.FullName.Substring($Source.Length).TrimStart('\')
        $destinationPath = Join-Path -Path $Destination -ChildPath $relativePath

        if ($item.PSIsContainer) {
            if (-not (Test-Path -Path $destinationPath)) {
                try {
                    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                    Write-Host "Created directory: $destinationPath"
                }
                catch {
                    Write-Warning "Failed to create directory '$destinationPath': $_"
                }
            }
        }
        else {
            $copyFile = $false
            if (-not (Test-Path -Path $destinationPath)) {
                $copyFile = $true
            }
            else {
                # Compare file sizes and LastWriteTime to decide if copy is needed.
                $destFile = Get-Item -Path $destinationPath
                if (($destFile.Length -ne $item.Length) -or ($destFile.LastWriteTime -lt $item.LastWriteTime)) {
                    $copyFile = $true
                }
            }
            if ($copyFile) {
                $attempt = 0
                $copied = $false
                while (-not $copied -and $attempt -lt $RetryCount) {
                    $attempt++
                    try {
                        Copy-Item -Path $item.FullName -Destination $destinationPath -Force -ErrorAction Stop
                        Write-Host "Copied/Updated file: $destinationPath"
                        $copied = $true
                    }
                    catch {
                        Write-Warning "Attempt $(attempt): Failed to copy file '$($item.FullName)' to '$destinationPath': $_"
                        if ($attempt -lt $RetryCount) {
                            Write-Host "Retrying in $RetryDelay milliseconds..."
                            Start-Sleep -Milliseconds $RetryDelay
                        }
                        else {
                            Write-Warning "Exceeded maximum retry attempts for file: $destinationPath"
                        }
                    }
                }
            }
        }
    }
    Write-Host "Target directory synchronized successfully."
}


function Copy-GitRepoSnapshot {
    <#
    .SYNOPSIS
    Updates a target directory to mirror the latest snapshot of a remote Git repository branch.

    .DESCRIPTION
    This function updates an existing target directory (which may not be empty) to match the state of a specified remote Git repository branch.
    It performs the following steps:
      1. Validates that the remote repository is accessible and that the specified branch exists.
      2. Clones a shallow snapshot (depth 1) of the branch into a temporary folder.
      3. Removes the .git folder from the temporary snapshot to eliminate Git versioning.
      4. Derives a safe repository name from the RepositoryUrl and appends it to the target directory.
      5. Calls Mirror-DirectorySnapshot to mirror the temporary snapshot to the repository-named subdirectory.
      6. Cleans up the temporary snapshot folder.

    .PARAMETER BranchName
    The name of the branch to fetch the snapshot from. This parameter is mandatory.

    .PARAMETER RepositoryUrl
    The URL of the remote Git repository. Defaults to "https://github.com/example/repo.git" if not provided.

    .PARAMETER Destination
    The target directory to be updated with the snapshot. If not provided or null, a temporary folder is used.

    .EXAMPLE
    Copy-GitRepoSnapshot -BranchName "main" -Destination "C:\MyProject"
    Updates the "C:\MyProject" directory (with the repository name appended) to mirror the latest snapshot of the "main" branch from the remote repository.
    #>
    [CmdletBinding()]
    [alias("cgrs")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BranchName,
        
        [Parameter(Mandatory = $false)]
        [string]$RepositoryUrl = "https://github.com/example/repo.git",
        
        [Parameter(Mandatory = $false)]
        [string]$Destination
    )

    # If Destination is not provided or is empty, create a temporary folder for the target.
    if ([string]::IsNullOrWhiteSpace($Destination)) {
        $tempPath = [System.IO.Path]::GetTempPath()
        $Destination = Join-Path -Path $tempPath -ChildPath ("RepoSnapshot_" + [System.Guid]::NewGuid().ToString())
        Write-Host "No destination provided. Using temporary folder as target: $Destination"
    }

    # Ensure the target directory exists.
    if (-not (Test-Path -Path $Destination)) {
        try {
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Error "Failed to create destination folder '$Destination': $_"
            return
        }
    }

    # Validate that the remote repository exists.
    Write-Host "Checking if repository exists at $RepositoryUrl..."
    try {
        $remoteRefs = git ls-remote $RepositoryUrl 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($remoteRefs)) {
            Write-Error "Remote repository does not exist or is inaccessible."
            return
        }
    }
    catch {
        Write-Error "Error while checking repository: $_"
        return
    }

    # Validate that the specified branch exists in the remote repository.
    Write-Host "Checking if branch '$BranchName' exists in the repository..."
    try {
        $branchRef = git ls-remote --heads $RepositoryUrl $BranchName 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($branchRef)) {
            Write-Error "Branch '$BranchName' does not exist in the repository."
            return
        }
    }
    catch {
        Write-Error "Error while checking branch: $_"
        return
    }

    # Create a temporary folder for the snapshot clone.
    $tempPath = [System.IO.Path]::GetTempPath()
    $tempSnapshotDir = Join-Path -Path $tempPath -ChildPath ("RepoSnapshot_" + [System.Guid]::NewGuid().ToString())
    try {
        New-Item -Path $tempSnapshotDir -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Error "Failed to create temporary snapshot folder '$tempSnapshotDir': $_"
        return
    }

    # Clone the repository snapshot into the temporary folder.
    Write-Host "Cloning branch '$BranchName' from repository '$RepositoryUrl' into temporary folder..."
    git clone --depth 1 -b $BranchName $RepositoryUrl $tempSnapshotDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git clone operation failed."
        return
    }

    # Remove the .git folder from the temporary snapshot to eliminate Git versioning.
    $gitFolder = Join-Path -Path $tempSnapshotDir -ChildPath ".git"
    if (Test-Path -Path $gitFolder) {
        Write-Host "Removing Git versioning from temporary snapshot..."
        try {
            Remove-Item -Path $gitFolder -Recurse -Force
            Write-Host ".git folder removed successfully."
        }
        catch {
            Write-Warning "Failed to remove .git folder: $_"
        }
    }
    else {
        Write-Warning ".git folder not found in temporary snapshot."
    }

    # Derive a safe repository name from the RepositoryUrl.
    try {
        $repoName = Get-SafeDirectoryNameFromUrl -RepositoryUrl $RepositoryUrl
        if ([string]::IsNullOrWhiteSpace($repoName)) {
            throw "Repository name could not be determined from URL."
        }
        $finalDestination = Join-Path -Path $Destination -ChildPath $repoName

        # Ensure the final destination directory exists.
        if (-not (Test-Path -Path $finalDestination)) {
            New-Item -Path $finalDestination -ItemType Directory -Force | Out-Null
        }
    }
    catch {
        Write-Error "Error determining repository name: $_"
        return
    }

    # Use the helper function to mirror the snapshot.
    Mirror-DirectorySnapshot -Source $tempSnapshotDir -Destination $finalDestination

    # Clean up the temporary snapshot folder.
    Write-Host "Cleaning up temporary snapshot folder..."
    try {
        Remove-Item -Path $tempSnapshotDir -Recurse -Force
        Write-Host "Temporary folder removed."
    }
    catch {
        Write-Warning "Failed to remove temporary folder '$tempSnapshotDir': $_"
    }
}

function Get-RemoteRepoFileInfo {
    <#
    .SYNOPSIS
        Retrieves file commit information from a remote Git repository without downloading full file contents.

    .DESCRIPTION
        This function accepts a remote Git repository URL and a branch name as parameters.
        It creates a temporary clone that only downloads metadata (using --filter=blob:none and --no-checkout)
        to prevent downloading the file blobs. It then lists all files from the HEAD commit and, for each file,
        extracts the latest commit's timestamp (converted to a DateTime object) and commit message.
        The function returns a PSCustomObject containing:
          - RemoteRepo: The provided remote repository URL.
          - BranchName: The branch name queried.
          - Files: A hashtable indexed by filename with file commit info.

    .PARAMETER RemoteRepo
        The URL of the remote Git repository.

    .PARAMETER BranchName
        The branch name to query.

    .EXAMPLE
        $result = Get-RemoteRepoFileInfo -RemoteRepo "https://github.com/user/repo.git" -BranchName "main"
        # $result.RemoteRepo contains the repo URL,
        # $result.BranchName contains "main",
        # $result.Files is a hashtable with file commit info.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRepo,
        
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    # Create a temporary directory for the partial clone.
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString()))

    try {
        # Clone the remote repo using partial clone options to fetch only metadata.
        git clone --filter=blob:none --no-checkout -b $BranchName $RemoteRepo $tempDir.FullName | Out-Null
        
        # Change into the temporary repository directory.
        Push-Location $tempDir.FullName
        
        # Get the list of files from the HEAD commit (metadata only, no file contents are present).
        $files = git ls-tree -r HEAD --name-only | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        
        # Prepare the result hashtable.
        $fileInfoHash = @{}

        foreach ($file in $files) {
            # Retrieve the latest commit info for the file using ISO strict date format.
            $commitInfo = git log -1 --pretty=format:"%ad|%s" --date=iso-strict -- $file
            
            if ($commitInfo) {
                $parts = $commitInfo -split "\|", 2
                # Convert the timestamp string to a DateTime object.
                $timestamp = [datetime]::Parse($parts[0])
                $comment = if ($parts.Count -gt 1) { $parts[1] } else { "" }
            }
            else {
                $timestamp = $null
                $comment = ""
            }
            
            # Add the file's commit information to the result hashtable.
            $fileInfoHash[$file] = [PSCustomObject]@{
                Filename  = $file
                Timestamp = $timestamp
                Comment   = $comment
            }
        }
        
        # Create the final output object.
        $output = [PSCustomObject]@{
            RemoteRepo = $RemoteRepo
            BranchName = $BranchName
            Files      = $fileInfoHash
        }
        
        return $output
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        # Restore the original location.
        Pop-Location
        
        # Clean up the temporary directory.
        if (Test-Path $tempDir.FullName) {
            Remove-Item $tempDir.FullName -Recurse -Force
        }
    }
}

function Get-RemoteRepoFiles {
    <#
    .SYNOPSIS
        Checks out selected files from a remote Git repository using sparse checkout,
        then detaches versioning by removing the .git folder.

    .DESCRIPTION
        This function accepts a remote repository URL, branch name, and a hashtable (or collection)
        of file information (e.g. as returned from Get-RemoteRepoFileInfo). It creates a temporary clone 
        using partial clone options (--filter=blob:none and --no-checkout) so that only repository metadata
        is downloaded. It then initializes sparse checkout (in non-cone mode) and sets the sparse-checkout 
        paths to the list of files (extracted from the keys of the provided hashtable). The branch is checked out,
        fetching only the specified files. After checkout, the .git directory is removed to detach versioning.
        
        The function returns a PSCustomObject containing:
          - RemoteRepo: The remote repository URL.
          - BranchName: The branch checked out.
          - LocalPath: The path to the temporary directory containing the checked-out files (with versioning detached).
          - Files: The list of files checked out.
          
    .PARAMETER RemoteRepo
        The URL of the remote Git repository.

    .PARAMETER BranchName
        The branch name to check out.

    .PARAMETER Files
        A hashtable or object with keys representing the file paths to be checked out.

    .EXAMPLE
        $nfo = Get-RemoteRepoFileInfo -RemoteRepo "https://github.com/user/repo.git" -BranchName "main"
        Get-RemoteRepoFiles -RemoteRepo $nfo.RemoteRepo -BranchName $nfo.BranchName -Files $nfo.Files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRepo,
        
        [Parameter(Mandatory = $true)]
        [string]$BranchName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Files
    )

    # Create a temporary directory for the sparse clone.
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString()))

    try {
        # Clone the remote repo using partial clone options to fetch only metadata.
        git clone --filter=blob:none --no-checkout -b $BranchName $RemoteRepo $tempDir.FullName | Out-Null

        # Change into the repository directory.
        Push-Location $tempDir.FullName

        # Initialize sparse checkout in non-cone mode.
        git sparse-checkout init --no-cone | Out-Null
        
        # Extract the file list from the keys of the Files hashtable.
        $fileList = $Files.Keys

        # Set sparse-checkout paths to only include the specified files.
        git sparse-checkout set $fileList | Out-Null

        # Checkout the branch to retrieve the sparse content.
        git checkout $BranchName | Out-Null

        # Detach versioning by removing the .git directory.
        $gitDir = Join-Path $tempDir.FullName ".git"
        if (Test-Path $gitDir) {
            Remove-Item -Recurse -Force $gitDir
        }

        # Create the output object.
        $output = [PSCustomObject]@{
            RemoteRepo = $RemoteRepo
            BranchName = $BranchName
            LocalPath  = $tempDir.FullName
            Files      = $fileList
        }
        return $output
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Pop-Location
    }
}

function Filter-RemoteFileInfoForCheckout {
    <#
    .SYNOPSIS
        Separates remote file info into files to check out versus blacklisted files based on local file UTC last write times.

    .DESCRIPTION
        This function accepts a hashtable of remote file information (with each key representing a file path relative
        to the repository root and each value containing at least a Timestamp property as a UTC DateTime) and a
        destination directory to compare against. It compares each remote file’s Timestamp with the corresponding
        local file’s LastWriteTimeUtc:
          - If the local file does not exist or is older than the remote version, the remote file info is placed into
            the RemoteNewer group.
          - Otherwise (i.e. the local file is up-to-date or newer), the file is added to the RemoteOlder group.
        The function returns a PSCustomObject with two properties:
          - RemoteNewer: A hashtable of files that should be checked out.
          - RemoteOlder: A hashtable of files that should be skipped in later checkout operations.

    .PARAMETER Files
        A hashtable where each key is a file path (relative to the repository root) and each value is an object
        containing file commit information, including a Timestamp property (as a UTC DateTime).

    .PARAMETER CompareDestination
        The path to the destination directory against which the file timestamps are compared.

    .EXAMPLE
        $nfo = Get-RemoteRepoFileInfo -BranchName "main" -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git"
        $result = Filter-RemoteFileInfoForCheckout -Files $nfo.Files -CompareDestination "C:\temp\test\BlackBytesBox.Manifested.GitX"
        # $result.RemoteNewer contains remote files that should be checked out,
        # $result.RemoteOlder contains files that are up-to-date locally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Files,
        [Parameter(Mandatory=$true)]
        [string]$CompareDestination
    )

    # Initialize output hashtables.
    $RemoteNewer = @{}
    $RemoteOlder = @{}

    # If the destination directory doesn't exist, create it and assume no local files exist.
    if (-not (Test-Path -Path $CompareDestination)) {
        New-Item -ItemType Directory -Path $CompareDestination -Force | Out-Null
        # Return all files for checkout.
        return [PSCustomObject]@{
            RemoteNewer = $Files
            RemoteOlder = @{}
        }
    }

    # Get all local files recursively under the destination directory.
    $localFiles = Get-ChildItem -Path $CompareDestination -Recurse -File -ErrorAction SilentlyContinue

    # Build a dictionary of local files keyed by their relative path (normalized).
    $localFilesDict = @{}
    foreach ($localFile in $localFiles) {
        # Compute relative path by removing the destination directory prefix.
        $relativePath = $localFile.FullName.Substring($CompareDestination.Length).TrimStart('\','/')
        $localFilesDict[$relativePath] = $localFile
    }

    # If no local files are found, consider all remote files as RemoteNewer.
    if ($localFilesDict.Count -eq 0) {
        return [PSCustomObject]@{
            RemoteNewer = $Files
            RemoteOlder = @{}
        }
    }

    # Compare each remote file with its local counterpart.
    foreach ($remotePath in $Files.Keys) {
        # Normalize remote file path to use OS-specific directory separators.
        $normalizedRemotePath = $remotePath -replace '/', [IO.Path]::DirectorySeparatorChar
        if (-not $localFilesDict.ContainsKey($normalizedRemotePath)) {
            # No local file exists; include in RemoteNewer.
            $RemoteNewer[$remotePath] = $Files[$remotePath]
        }
        else {
            $localFile = $localFilesDict[$normalizedRemotePath]
            $localTime = $localFile.LastWriteTimeUtc
            $remoteTime = $Files[$remotePath].Timestamp
            if ($localTime -lt $remoteTime) {
                # Local file is older; include for checkout.
                $RemoteNewer[$remotePath] = $Files[$remotePath]
            }
            else {
                # Local file is up-to-date or newer; add to RemoteOlder.
                $RemoteOlder[$remotePath] = $Files[$remotePath]
            }
        }
    }

    return [PSCustomObject]@{
        RemoteNewer = $RemoteNewer
        RemoteOlder = $RemoteOlder
    }
}



$nfo = Get-RemoteRepoFileInfo -BranchName "main" -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git"
$nfo.Files = Filter-RemoteFileInfoForCheckout -Files $nfo.Files -CompareDestination "C:\temp\test\BlackBytesBox.Manifested.GitX"
$files = Get-RemoteRepoFiles -BranchName "$($nfo.BranchName)" -RemoteRepo "$($nfo.RemoteRepo)" -Files $nfo.Files.RemoteNewer

Write-Output $files.LocalPath
$x = 1