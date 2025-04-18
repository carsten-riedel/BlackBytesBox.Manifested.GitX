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

function Get-GitCurrentBranchRoot {
    <#
    .SYNOPSIS
    Retrieves the root portion of the current Git branch name.

    .DESCRIPTION
    This function retrieves the current Git branch name by invoking Git commands directly.
    It first attempts to get the branch name using 'git rev-parse --abbrev-ref HEAD'. If the result is
    "HEAD" (indicating a detached HEAD state), it then looks for a branch that contains the current commit
    via 'git branch --contains HEAD'. If no branch is found, it falls back to using the commit hash.
    The function then splits the branch name on both forward (/) and backslashes (\) and returns the first
    segment as the branch root.

    .EXAMPLE
    PS C:\> Get-GitCurrentBranchRoot

    Returns:
    feature

    .NOTES
    - Ensure Git is available in your system's PATH.
    - For detached HEAD states with multiple containing branches, the first branch found is used.
    #>
    [CmdletBinding()]
    [alias("ggcbr")]
    param()

    try {
        # Attempt to get the abbreviated branch name.
        $branch = git rev-parse --abbrev-ref HEAD 2>$null

        # Check for detached HEAD state.
        if ($branch -eq 'HEAD') {
            # Retrieve branches containing the current commit.
            $branches = git branch --contains HEAD 2>$null | ForEach-Object {
                $_.Replace('*','').Trim()
            } | Where-Object { $_ -ne '' }

            if ($branches.Count -gt 0) {
                $branch = $branches[0]
            }
            else {
                # Fallback to commit hash if no branch is found.
                $branch = git rev-parse HEAD 2>$null
            }
        }
        
        $branch = $branch.Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Error "Unable to determine the current Git branch."
            return
        }
        
        # Split the branch name on both '/' and '\' and return the first segment.
        $root = $branch -split '[\\/]' | Select-Object -First 1
        return $root
    }
    catch {
        Write-Error "Error retrieving Git branch root: $_"
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
    This function synchronizes the destination directory with the source directory. It supports three modes:
      - Missing: Only copy items that do not exist in the destination.
      - SmartSync (default): Update items only if the source file is newer or has a different size.
      - All: Copy every item from the source to the destination regardless of file attributes.
    Additionally, if -PurgeExtraFiles is enabled (default $true), any files or directories in the destination that do not exist in the source are removed.
    The function includes simple retry logic for file copy operations in case target files are in use.

    .PARAMETER Source
    The source directory path.

    .PARAMETER Destination
    The destination directory path.

    .PARAMETER RetryCount
    The number of times to retry a failed file copy operation. Defaults to 10.

    .PARAMETER RetryDelay
    The delay in milliseconds between retry attempts. Defaults to 6000 (6 seconds).

    .PARAMETER Mode
    The copy mode to use. Valid values are:
        - Missing: Only copy missing items.
        - SmartSync: Copy missing items and update outdated items (default).
        - All: Copy all files unconditionally.

    .PARAMETER PurgeExtraFiles
    Indicates whether files and directories in the destination that do not exist in the source should be removed.
    Defaults to $true.

    .EXAMPLE
    Mirror-DirectorySnapshot -Source "C:\Temp\Snapshot" -Destination "C:\MyProject\repo" -RetryCount 5 -RetryDelay 3000 -Mode All -PurgeExtraFiles $true
    Mirrors the snapshot directory to the specified destination with up to 5 retries, a 3000-millisecond delay between retries,
    copying all files unconditionally and purging extra files.
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
        [int]$RetryDelay = 6000,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Missing", "SmartSync", "All")]
        [string]$Mode = "SmartSync",

        [Parameter(Mandatory = $false)]
        [bool]$PurgeExtraFiles = $true
    )

    Write-Host "Synchronizing target directory '$Destination' with the snapshot in '$Mode' mode..."

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

    # Purge extra files if enabled.
    if ($PurgeExtraFiles) {
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
                # File is missing, so always copy.
                $copyFile = $true
            }
            else {
                switch ($Mode) {
                    "Missing" { $copyFile = $false }  # Do not update existing files.
                    "SmartSync" {
                        # Only update if source file is different.
                        $destFile = Get-Item -Path $destinationPath
                        if (($destFile.Length -ne $item.Length) -or ($destFile.LastWriteTime -lt $item.LastWriteTime)) {
                            $copyFile = $true
                        }
                    }
                    "All" { $copyFile = $true }  # Always copy file.
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
                        Write-Warning "Attempt $($attempt): Failed to copy file '$($item.FullName)' to '$destinationPath': $_"
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

function Restore-GitFileTimes {
    <#
    .SYNOPSIS
    Restores original file timestamps based on the last commit times in a Git repository.
    
    .DESCRIPTION
    Iterates over all files (excluding the .git folder) in the specified repository directory.
    For each file, it retrieves the most recent commit timestamp using Git and updates the file's LastWriteTime accordingly.
    
    .PARAMETER RepoDir
    The root directory of the cloned Git repository.
    
    .EXAMPLE
    Restore-GitFileTimes -RepoDir "C:\Temp\RepoSnapshot"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoDir
    )
    
    Write-Host "Restoring original file timestamps from Git commit dates..."
    # Get all files recursively, excluding the .git folder.
    $files = Get-ChildItem -Path $RepoDir -Recurse -File | Where-Object { $_.FullName -notmatch '\\.git\\' }
    
    foreach ($file in $files) {
        # Compute relative path required by git log.
        $relativePath = $file.FullName.Substring($RepoDir.Length).TrimStart('\')
        # Temporarily change directory to the repository root so Git can find the .git folder.
        $currentDir = Get-Location
        Set-Location $RepoDir
        # Retrieve the commit timestamp (Unix epoch) for the file.
        $commitTimeStr = git log -1 --format=%ct -- $relativePath 2>$null
        Set-Location $currentDir
        if ($commitTimeStr -and $commitTimeStr.Trim() -match '^\d+$') {
            $commitTime = [datetime]::UnixEpoch.AddSeconds([double]$commitTimeStr.Trim())
            try {
                $file.LastWriteTime = $commitTime
                Write-Host "Set timestamp for $($file.FullName) to $commitTime"
            }
            catch {
                Write-Warning "Failed to set timestamp for $($file.FullName): $_"
            }
        }
        else {
            Write-Warning "Could not retrieve commit time for $($file.FullName)."
        }
    }
}

function Copy-GitRepoSnapshot {
    <#
    .SYNOPSIS
    Updates a target directory to mirror a snapshot of a remote Git repository branch.
    
    .DESCRIPTION
    This function updates an existing target directory (which may not be empty) to match the state of a specified remote Git repository branch.
    It performs the following steps:
      1. Validates that the remote repository is accessible and that the specified branch exists.
      2. Clones a shallow snapshot (depth 1) of the branch into a temporary folder.
      3. Optionally selects a subfolder within the clone if specified; if not, the clone root is used.
      4. Restores original file timestamps from Git commit dates.
      5. Removes the .git folder from the temporary snapshot to eliminate Git versioning.
      6. Calls Mirror-DirectorySnapshot to mirror the selected snapshot to the target directory.
      7. Cleans up the temporary snapshot folder.
    
    .PARAMETER BranchName
    The name of the branch to fetch the snapshot from. This parameter is mandatory.
    
    .PARAMETER RepositoryUrl
    The URL of the remote Git repository. This parameter is mandatory and must be in a valid format (e.g. starting with http://, https://, or git@).
    
    .PARAMETER Destination
    The target directory to be updated with the snapshot. If not provided or null, a temporary folder is used.
    
    .PARAMETER Subfolder
    An optional subfolder (relative to the clone root) within the temporary snapshot directory to be copied to the destination.
    If not specified, the entire clone root is used.
    
    .EXAMPLE
    Copy-GitRepoSnapshot -BranchName "main" -RepositoryUrl "https://github.com/example/repo.git" -Destination "C:\MyProject" -Subfolder "src"
    Updates the "C:\MyProject" directory to mirror the snapshot of the "src" subfolder from the cloned repository.
    #>
    [CmdletBinding()]
    [alias("cgrs")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BranchName,
        
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl,
        
        [Parameter(Mandatory = $false)]
        [string]$Destination,
        
        [Parameter(Mandatory = $false)]
        [string]$Subfolder
    )
    
    # Check if RepositoryUrl is provided and not empty.
    if ([string]::IsNullOrWhiteSpace($RepositoryUrl)) {
        Write-Error "RepositoryUrl is mandatory and must be provided."
        return
    }
    
    # Validate that RepositoryUrl is in a recognized format.
    if ($RepositoryUrl -notmatch '^(https?:\/\/|git@)') {
        Write-Error "RepositoryUrl '$RepositoryUrl' is not in a recognized format. Please provide a valid remote Git repository URL."
        return
    }
    
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
    
    # Restore original file timestamps from git commit dates.
    Restore-GitFileTimes -RepoDir $tempSnapshotDir
    
    # Determine the source directory to copy.
    $sourceToCopy = $tempSnapshotDir
    if (-not [string]::IsNullOrWhiteSpace($Subfolder)) {
        $sourceToCopy = Join-Path -Path $tempSnapshotDir -ChildPath $Subfolder
        if (-not (Test-Path -Path $sourceToCopy)) {
            Write-Error "Specified subfolder '$Subfolder' does not exist in the cloned repository."
            return
        }
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
    
    Mirror-DirectorySnapshot -Source $sourceToCopy -Destination $Destination -RetryCount 5 -RetryDelay 3000 -PurgeExtraFiles $true
    
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
    [alias("grrfi")]
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
                try {
                    # Use DateTimeOffset::ParseExact to accurately parse the ISO 8601 timestamp with timezone offset.
                    $timestampOffset = [DateTimeOffset]::ParseExact($parts[0], "yyyy-MM-ddTHH:mm:sszzz", $null)
                    # Optionally, convert to a DateTime in local time:
                    $timestamp = $timestampOffset.UtcDateTime
                    # Alternatively, if you want to retain offset information, you could store $timestampOffset directly.
                }
                catch {
                    Write-Warning "Failed to parse timestamp '$($parts[0])'."
                    $timestamp = $null
                }
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
    [alias("grrf")]
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

        if (-not $fileList -or $fileList.Count -eq 0) {
            Write-Output "No files specified. Aborting sparse checkout; returning empty file list."
            
            # Create the output object with an empty Files array.
            $output = [PSCustomObject]@{
                RemoteRepo = $RemoteRepo
                BranchName = $BranchName
                LocalPath  = $tempDir.FullName
                Files      = @()  # Empty array
            }
            return $output
        }

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

function Compare-LocalRemoteFileTimestamps {
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
        $result = Compare-LocalRemoteFileTimestamps-Files $nfo.Files -CompareDestination "C:\temp\test\BlackBytesBox.Manifested.GitX"
        # $result.RemoteNewer contains remote files that should be checked out,
        # $result.RemoteOlder contains files that are up-to-date locally.
    #>
    [CmdletBinding()]
    [alias("clrft")]
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

function Copy-DirectorySnapshot {
    <#
    .SYNOPSIS
        Copies a directory snapshot from a source to a destination with optional overwrite, retry, and purge logic.

    .DESCRIPTION
        This function copies all files from the source directory to the destination directory while preserving the folder structure.
        If a destination file already exists, the function will either overwrite it when the -Overwrite switch is provided or skip copying and issue a warning.
        You can also specify how many retry attempts should be made and the delay between retries in case of a failure.
        When the -PurgeExtraFiles switch is used, the function will remove any extra files and directories in the destination that do not exist in the source.

    .PARAMETER Source
        The full path of the source directory.

    .PARAMETER Destination
        The full path of the destination directory.

    .PARAMETER RetryCount
        The number of retry attempts for copying a file if an error occurs. The default value is 5.

    .PARAMETER RetryDelay
        The delay in milliseconds between retry attempts. The default is 3000 ms.

    .PARAMETER Overwrite
        When set, existing files in the destination will be overwritten. If omitted, existing files are skipped and a warning is issued.

    .PARAMETER PurgeExtraFiles
        When set, extra files and directories in the destination that are not present in the source will be removed.

    .EXAMPLE
        Copy-DirectorySnapshot -Source "C:\SourceDir" -Destination "C:\DestDir" -RetryCount 3 -RetryDelay 2000 -Overwrite -PurgeExtraFiles
        # This copies files from C:\SourceDir to C:\DestDir, overwriting existing files, purging extra files/dirs, with up to 3 retries and a 2000ms delay between attempts.

    .EXAMPLE
        Copy-DirectorySnapshot -Source "C:\SourceDir" -Destination "C:\DestDir"
        # This copies files without overwriting files that already exist, and a warning is shown for each file that is skipped.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [int]$RetryCount = 5,

        [int]$RetryDelay = 3000,

        [switch]$Overwrite,

        [switch]$PurgeExtraFiles
    )

    # Check if source exists.
    if (-not (Test-Path -Path $Source -PathType Container)) {
        Write-Error "Source directory '$Source' does not exist."
        return
    }

    # Create destination directory if it doesn't exist.
    if (-not (Test-Path -Path $Destination -PathType Container)) {
        Write-Verbose "Destination '$Destination' does not exist. Creating..."
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    # Retrieve all files recursively from the source.
    $sourceFiles = Get-ChildItem -Path $Source -Recurse -File

    foreach ($file in $sourceFiles) {
        # Determine the file's relative path and corresponding destination path.
        $relativePath = $file.FullName.Substring($Source.Length).TrimStart('\')
        $destFile = Join-Path -Path $Destination -ChildPath $relativePath

        # Ensure the destination directory for this file exists.
        $destDir = Split-Path -Path $destFile -Parent
        if (-not (Test-Path -Path $destDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        # If the destination file exists, decide what to do based on the Overwrite switch.
        if (Test-Path -Path $destFile) {
            if ($Overwrite) {
                $action = "Overwriting"
            }
            else {
                Write-Warning "File '$destFile' already exists. Skipping copy."
                continue
            }
        }
        else {
            $action = "Copying"
        }

        # Attempt to copy the file with retries.
        $attempt = 0
        while ($attempt -le $RetryCount) {
            try {
                # Copy-Item supports -Force, which will overwrite the destination if it exists.
                Copy-Item -Path $file.FullName -Destination $destFile -Force:$Overwrite -ErrorAction Stop
                Write-Output "$action file '$destFile' from source '$($file.FullName)'."
                break  # Success; exit retry loop.
            }
            catch {
                $attempt++
                if ($attempt -gt $RetryCount) {
                    Write-Warning "Failed to copy '$($file.FullName)' to '$destFile' after $RetryCount attempts. Error: $_"
                }
                else {
                    Start-Sleep -Milliseconds $RetryDelay
                }
            }
        }
    }

    # Purge extra files and directories in destination if requested.
    if ($PurgeExtraFiles) {
        Write-Verbose "Purging extra files and directories from destination '$Destination'."

        # Build a set of relative file paths that exist in the source.
        $sourceRelativeFiles = $sourceFiles | ForEach-Object {
            $_.FullName.Substring($Source.Length).TrimStart('\')
        }

        # Remove extra files in destination.
        $destFiles = Get-ChildItem -Path $Destination -Recurse -File
        foreach ($destFile in $destFiles) {
            $relativePath = $destFile.FullName.Substring($Destination.Length).TrimStart('\')
            if ($sourceRelativeFiles -notcontains $relativePath) {
                try {
                    Remove-Item -Path $destFile.FullName -Force -ErrorAction Stop
                    Write-Output "Removed extra file '$($destFile.FullName)'."
                }
                catch {
                    Write-Warning "Failed to remove extra file '$($destFile.FullName)'. Error: $_"
                }
            }
        }

        # Build a set of relative directory paths that exist in the source.
        $sourceDirs = Get-ChildItem -Path $Source -Recurse -Directory | ForEach-Object {
            $_.FullName.Substring($Source.Length).TrimStart('\')
        }

        # Remove extra directories in destination that are not present in the source.
        # Sorting in descending order ensures deeper directories are removed first.
        $destDirs = Get-ChildItem -Path $Destination -Recurse -Directory |
                    Sort-Object { $_.FullName.Split('\').Count } -Descending
        foreach ($destDir in $destDirs) {
            $relativePath = $destDir.FullName.Substring($Destination.Length).TrimStart('\')
            if ($sourceDirs -notcontains $relativePath) {
                try {
                    Remove-Item -Path $destDir.FullName -Force -Recurse -ErrorAction Stop
                    Write-Output "Removed extra directory '$($destDir.FullName)'."
                }
                catch {
                    Write-Warning "Failed to remove extra directory '$($destDir.FullName)'. Error: $_"
                }
            }
        }
    }
}

function Sync-RemoteRepoFiles {
    <#
    .SYNOPSIS
        Synchronizes files from a remote Git repository to a local destination.

    .DESCRIPTION
        This function performs the following steps:
          1. Retrieves commit and file information from a remote Git repository.
          2. Compares remote file timestamps with those in a specified local destination.
          3. Performs a sparse checkout of the remote repository for files that are newer than the local copies.
          4. Copies the checked-out files to the local destination with an option to overwrite existing files.
          5. When the -PurgeExtraFiles switch is set, extra files and directories in the local destination that do not exist in the remote repository (based on $remoteFileInfo.Files) are purged.

    .PARAMETER RemoteRepo
        The URL of the remote Git repository.

    .PARAMETER BranchName
        The branch to operate on.

    .PARAMETER LocalDestination
        The local directory that serves as the destination for file comparison and copy.

    .PARAMETER PurgeExtraFiles
        When set, extra files and directories in the local destination that are not present in the remote repository will be removed.

    .EXAMPLE
        Sync-RemoteRepoFiles -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX" -BranchName "main" -LocalDestination "C:\temp\test" -PurgeExtraFiles
        # This synchronizes the remote repository to the local destination, overwriting outdated files and purging extra files and directories.
    #>
    [CmdletBinding()]
    [alias("srrf")]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRepo,
        
        [Parameter(Mandatory = $true)]
        [string]$BranchName,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalDestination,
        
        [switch]$PurgeExtraFiles
    )
    
    try {
        Write-Verbose "Retrieving remote repository file information..."
        $remoteFileInfo = Get-RemoteRepoFileInfo -RemoteRepo $RemoteRepo -BranchName $BranchName
       
        if (-not $remoteFileInfo.Files -or $remoteFileInfo.Files.Count -eq 0) {
            Write-Verbose "No remote files found in repository."
        }
        else {
            Write-Verbose "Comparing local files with remote file timestamps..."
            $timeCompareResult = Compare-LocalRemoteFileTimestamps -Files $remoteFileInfo.Files -CompareDestination $LocalDestination

            if ($timeCompareResult.RemoteNewer -and $timeCompareResult.RemoteNewer.Count -gt 0) {
                Write-Verbose "Performing sparse checkout for files with newer remote versions..."
                $clonedFiles = Get-RemoteRepoFiles -RemoteRepo $remoteFileInfo.RemoteRepo -BranchName $remoteFileInfo.BranchName -Files $timeCompareResult.RemoteNewer
                
                Write-Verbose "Copying updated files to local destination..."
                # Copy updated files from the sparse checkout location to the local destination.
                Copy-Item -Path (Join-Path $clonedFiles.LocalPath '*') -Destination $LocalDestination -Recurse -Force -ErrorAction Stop
            }
            else {
                Write-Verbose "No remote files to sync."
            }
        }
        
        if ($PurgeExtraFiles) {
            Write-Verbose "Purging extra files from local destination based on remote repository file list..."
            # Normalize remote file paths by replacing forward slashes with backslashes.
            $remoteRelativePaths = $remoteFileInfo.Files | ForEach-Object { ($_.Keys) -replace '/', '\' }
            
            # Purge extra files.
            $localFiles = Get-ChildItem -Path $LocalDestination -Recurse -File
            foreach ($localFile in $localFiles) {
                $localRelativePath = ($localFile.FullName.Substring($LocalDestination.Length).TrimStart('\')) -replace '/', '\'
                if ($remoteRelativePaths -notcontains $localRelativePath) {
                    try {
                        Remove-Item -Path $localFile.FullName -Force -ErrorAction Stop
                        Write-Output "Removed extra file '$($localFile.FullName)'."
                    }
                    catch {
                        Write-Warning "Failed to remove extra file '$($localFile.FullName)'. Error: $_"
                    }
                }
            }
            
            Write-Verbose "Purging extra directories from local destination..."
            # Remove extra directories that are now empty.
            $localDirs = Get-ChildItem -Path $LocalDestination -Recurse -Directory |
                         Sort-Object { $_.FullName.Split('\').Count } -Descending
            foreach ($dir in $localDirs) {
                if (-not (Get-ChildItem -Path $dir.FullName)) {
                    try {
                        Remove-Item -Path $dir.FullName -Force -Recurse -ErrorAction Stop
                        Write-Output "Removed extra directory '$($dir.FullName)'."
                    }
                    catch {
                        Write-Warning "Failed to remove extra directory '$($dir.FullName)'. Error: $_"
                    }
                }
            }
        }
        
        Write-Output "Sync complete."
    }
    catch {
        Write-Error "An error occurred during synchronization: $_"
    }
}


<#
.SYNOPSIS
Gets filtered asset names, version, download URLs—and optionally downloads them into structured subfolders with version support.

.DESCRIPTION
Parses the provided GitHub repo URL, fetches the latest release’s assets, and:
- Lists Name, Version, DownloadUrl, and Path for each asset.
- Default DownloadFolder is the user's Downloads folder if not specified.
- By default, each asset is placed in its own subfolder; use –NoSubfolder to disable per-asset subfolders.
- If –IncludeVersionFolder is used, prepends the release tag as a version folder under DownloadFolder.
- If –Extract is used, ZIPs are downloaded to a temp folder, extracted into the target directory (with overwrite), and temporary files cleaned.
- The return `Path` property will be the full file path for non-extracted assets or the directory path where contents were extracted.

.PARAMETER RepoUrl
Full URL of the GitHub repository (e.g. https://github.com/owner/repo).

.PARAMETER Filter
Wildcard patterns; only assets whose names match *every* pattern are included.

.PARAMETER DownloadFolder
Root folder where assets (or their subfolders) will be placed. Defaults to "$HOME\Downloads" if not provided.

.PARAMETER NoSubfolder
Switch: when present, disables creation of per-asset subfolders (default is to use subfolders).

.PARAMETER IncludeVersionFolder
Switch: when present, inserts a version folder (the release tag) under DownloadFolder before any subfolders.

.PARAMETER Extract
Switch: for ZIP assets, download to a temp folder, extract (overwriting) into the target directory, then remove temp data.

.OUTPUTS
PSCustomObject with properties:
- Name
- Version
- DownloadUrl
- Path   # file path or extract directory

.EXAMPLE
# Download all assets into per-asset folders under a version folder
Get-GitHubLatestRelease `
  -RepoUrl 'https://github.com/ggml-org/llama.cpp' `
  -IncludeVersionFolder

.EXAMPLE
# Filter AVX2 x64 zips, download+extract into versioned folders without asset subfolders
Get-GitHubLatestRelease `
  -RepoUrl 'https://github.com/ggml-org/llama.cpp' `
  -Filter '*avx2*','*x64*' `
  -IncludeVersionFolder `
  -NoSubfolder `
  -Extract
#>
function Get-GitHubLatestRelease {
    [CmdletBinding()]
    [alias("gglr")]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoUrl,

        [Parameter(Position=1)]
        [string[]]$Filter,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DownloadFolder,

        [Parameter()]
        [switch]$NoSubfolder,

        [Parameter()]
        [switch]$IncludeVersionFolder,

        [Parameter()]
        [switch]$Extract
    )

    # Default DownloadFolder to user's Downloads if not provided
    if (-not $PSBoundParameters.ContainsKey('DownloadFolder')) {
        $DownloadFolder = Join-Path $HOME 'Downloads'
    }

    if ($Extract.IsPresent -and -not $DownloadFolder) {
        Write-Error "The –Extract switch requires the –DownloadFolder parameter."; return
    }

    # Determine subfolder usage: default true (use subfolders), disabled by -NoSubfolder
    $useSubfolder = -not $NoSubfolder.IsPresent

    # Parse owner/repo
    try {
        $segments = ([Uri]$RepoUrl).AbsolutePath.Trim('/') -split '/'
        if ($segments.Count -lt 2) { throw "Invalid URL format" }
        $owner, $repo = $segments[0], $segments[1]
    } catch {
        Write-Error "Failed to parse RepoUrl '${RepoUrl}': $($_.Exception.Message)"; return
    }

    # Fetch latest release
    try {
        $apiUri = "https://api.github.com/repos/${owner}/${repo}/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUri -Headers @{ Accept = 'application/vnd.github.v3+json' } -Method Get
    } catch {
        Write-Error "Failed to fetch latest release for ${owner}/${repo}: $($_.Exception.Message)"; return
    }

    $version = $release.tag_name
    $assets  = $release.assets

    # Apply filters
    if ($Filter) {
        $assets = $assets | Where-Object {
            $n = $_.name
            foreach ($pattern in $Filter) {
                if ($n -notlike $pattern) { return $false }
            }
            return $true
        }
    }

    # Ensure root folder exists
    if ($DownloadFolder -and -not (Test-Path $DownloadFolder)) {
        New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null
    }

    # Prepare temp for extract
    if ($Extract.IsPresent) {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    }

    # Process assets
    $results = foreach ($asset in $assets) {
        $name = $asset.name
        $url  = $asset.browser_download_url
        $targetDir = $DownloadFolder

        # Build directory path
        if ($IncludeVersionFolder) {
            $targetDir = Join-Path $targetDir $version
        }
        if ($useSubfolder) {
            $base = [IO.Path]::GetFileNameWithoutExtension($name)
            $targetDir = Join-Path $targetDir $base
        }
        if ($targetDir -and -not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        # Initialize path variable
        $path = $null

        # Download/extract
        if ($DownloadFolder) {
            if ($Extract.IsPresent -and $name -match '\.zip$') {
                $tempFile = Join-Path $tempDir $name
                Invoke-WebRequest -Uri $url -OutFile $tempFile -UseBasicParsing
                $zip = [System.IO.Compression.ZipFile]::OpenRead($tempFile)
                foreach ($entry in $zip.Entries) {
                    $destPath = Join-Path $targetDir $entry.FullName
                    $destDir  = Split-Path $destPath -Parent
                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    if ($entry.Name) {
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
                    }
                }
                $zip.Dispose()
                Remove-Item -Path $tempFile -Force
                # For extracted zips, Path is the directory
                $path = $targetDir
            } else {
                $destFile = Join-Path $targetDir $name
                Invoke-WebRequest -Uri $url -OutFile $destFile -UseBasicParsing
                # For non-extracted assets, Path is the file path
                $path = $destFile
            }
        }

        [PSCustomObject]@{
            Name        = $name
            Version     = $version
            DownloadUrl = $url
            Path        = $path
        }
    }

    # Cleanup
    if ($Extract.IsPresent) { Remove-Item -Path $tempDir -Recurse -Force }
    return $results
}

function Get-GitRepoFileMetadata {
    <#
    .SYNOPSIS
        Retrieves commit metadata for files in a Git repository and optionally constructs download URLs.

    .DESCRIPTION
        This function accepts a repository URL, branch name, and an optional download endpoint.
        It performs a partial clone (metadata only) to list files at the HEAD commit, retrieves each
        file's latest commit timestamp and message, and—if specified—generates a direct file
        download URL by injecting the endpoint segment.

    .PARAMETER RepoUrl
        The HTTP(S) URL of the remote Git repository (e.g., "https://huggingface.co/microsoft/phi-4").

    .PARAMETER BranchName
        The branch to inspect (e.g., "main").

    .PARAMETER DownloadEndpoint
        (Optional) The URL path segment to insert before the branch name for download links
        (e.g., 'resolve' or 'raw/refs/heads'). If omitted or empty, DownloadUrl for each file
        will be an empty string.

    .EXAMPLE
        # Without download endpoint
        $info = Get-GitRepoFileMetadata \
            -RepoUrl "https://huggingface.co/microsoft/phi-4" \
            -BranchName "main"
        # $info.Files['README.md'].DownloadUrl -> ""

    .EXAMPLE
        # With download endpoint
        $info = Get-GitRepoFileMetadata \
            -RepoUrl "https://huggingface.co/microsoft/phi-4" \
            -BranchName "main" \
            -DownloadEndpoint "resolve"
        # $info.Files['README.md'].DownloadUrl -> https://huggingface.co/microsoft/phi-4/resolve/main/README.md

    .OUTPUTS
        PSCustomObject with properties:
        - RepoUrl (string)
        - BranchName (string)
        - DownloadEndpoint (string, optional)
        - Files (hashtable of PSCustomObject with Filename, Timestamp, Comment, DownloadUrl)
    #>
    [CmdletBinding()]
    [alias('ggrfm')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BranchName,

        [Parameter()]
        [string]$DownloadEndpoint
    )

    # Prepare partial clone directory
    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        git clone --filter=blob:none --no-checkout -b $BranchName $RepoUrl $tempDir | Out-Null
        Push-Location $tempDir

        $files = git ls-tree -r HEAD --name-only | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
        $fileData = @{}

        foreach ($file in $files) {
            $commit = git log -1 --pretty=format:"%ad|%s" --date=iso-strict -- $file
            if ($commit) {
                $parts = $commit -split '\|',2
                try { $ts = [DateTimeOffset]::Parse($parts[0]).UtcDateTime } catch { $ts = $null }
                $msg = if ($parts.Length -gt 1) { $parts[1] } else { '' }
            } else {
                $ts  = $null
                $msg = ''
            }

            # Build download URL if endpoint given
            if ($PSBoundParameters.ContainsKey('DownloadEndpoint') -and $DownloadEndpoint) {
                $endpoint = $DownloadEndpoint.Trim('/')
                $base     = $RepoUrl.TrimEnd('/')
                $url      = "${base}/${endpoint}/${BranchName}/${file}"
            } else {
                $url = ''
            }

            $fileData[$file] = [PSCustomObject]@{
                Filename    = $file
                Timestamp   = $ts
                Comment     = $msg
                DownloadUrl = $url
            }
        }

        # Construct result
        $result = [ordered]@{
            RepoUrl        = $RepoUrl
            BranchName     = $BranchName
            Files          = $fileData
        }
        if ($PSBoundParameters.ContainsKey('DownloadEndpoint') -and $DownloadEndpoint) {
            $result.DownloadEndpoint = $DownloadEndpoint
        }

        return [PSCustomObject]$result
    }
    catch {
        Write-Error "Error retrieving metadata: $_"
    }
    finally {
        Pop-Location
        Remove-Item -Path $tempDir -Recurse -Force
    }
}

function Sync-GitRepoFiles {
    <#
    .SYNOPSIS
        Mirrors files from a GitRepoFileMetadata object to a local folder based on DownloadUrl, showing progress.

    .DESCRIPTION
        Takes metadata from Get-GitRepoFileMetadata and a destination root. It first removes any files
        in the local target that are not present in the metadata (cleanup), then classifies files as:
        "matched" (timestamps equal), "missing" (not present) or "stale" (timestamp mismatch), logs a summary,
        processes downloads in order (missing first, then stale), and finally reports completion.

    .PARAMETER Metadata
        PSCustomObject returned by Get-GitRepoFileMetadata.

    .PARAMETER DestinationRoot
        The root directory under which to sync files (e.g., "C:\Downloads").

    .OUTPUTS
        None. Writes progress and summary to the host.
    #>
    [CmdletBinding()]
    [alias('sgrf')]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][PSCustomObject]$Metadata,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DestinationRoot
    )

    Write-Host "Starting sync for: $($Metadata.RepoUrl)"
    $uri = [Uri]$Metadata.RepoUrl
    $repoPath = $uri.AbsolutePath.Trim('/')
    $targetDir = Join-Path $DestinationRoot $repoPath
    if (-not (Test-Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }
    Write-Host "Destination: $targetDir`n"

    # Initial cleanup: remove any files not in metadata
    Write-Host "Performing initial cleanup of extraneous files..."
    $expectedPaths = $Metadata.Files.Keys | ForEach-Object { Join-Path $targetDir $_ }
    Get-ChildItem -Path $targetDir -Recurse -File | ForEach-Object {
        if ($expectedPaths -notcontains $_.FullName) {
            Write-Host "Removing extra file: $($_.FullName)"
            Remove-Item -Path $_.FullName -Force
        }
    }
    Write-Host "Initial cleanup complete.`n"

    # Classification phase
    $missing = New-Object System.Collections.Generic.List[string]
    $stale   = New-Object System.Collections.Generic.List[string]
    $matched = New-Object System.Collections.Generic.List[string]

    foreach ($kv in $Metadata.Files.GetEnumerator()) {
        $fileName = $kv.Key; $info = $kv.Value
        if ([string]::IsNullOrEmpty($info.DownloadUrl)) {
            Write-Host "Skipping (no URL): $fileName"
            continue
        }
        $localPath = Join-Path $targetDir $fileName
        if (-not (Test-Path $localPath)) {
            $missing.Add($fileName)
        } else {
            $localTime = (Get-Item $localPath).LastWriteTimeUtc
            if ($localTime -eq $info.Timestamp) {
                $matched.Add($fileName)
            } else {
                $stale.Add($fileName)
            }
        }
    }

    # Summary
    Write-Host "Summary: $($matched.Count) up-to-date, $($missing.Count) missing, $($stale.Count) stale files.`n"

    # Download missing files first
    foreach ($fileName in $missing) {
        $info = $Metadata.Files[$fileName]
        $localPath = Join-Path $targetDir $fileName
        $destDir = Split-Path $localPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
        Write-Host "File not present, will download: $fileName"
        Invoke-WebRequest -Uri $info.DownloadUrl -OutFile $localPath -UseBasicParsing
        [System.IO.File]::SetLastWriteTimeUtc($localPath, $info.Timestamp)
        Write-Host "Downloaded and timestamp set: $fileName`n"
    }

    # Then re-download stale files
    foreach ($fileName in $stale) {
        $info = $Metadata.Files[$fileName]
        $localPath = Join-Path $targetDir $fileName
        Write-Host "Out-of-date (timestamp mismatch), will re-download: $fileName"
        Invoke-WebRequest -Uri $info.DownloadUrl -OutFile $localPath -UseBasicParsing
        [System.IO.File]::SetLastWriteTimeUtc($localPath, $info.Timestamp)
        Write-Host "Downloaded and timestamp set: $fileName`n"
    }

    # Finally, report matched files
    foreach ($fileName in $matched) {
        Write-Host "Timestamps match, skipping: $fileName"
    }

    Write-Host "Sync complete for: $($Metadata.RepoUrl)"
}



# PSScriptAnalyzer disable PSUseApprovedVerbs

function Mirror-GitRepoWithDownloadContent {
    <#
    .SYNOPSIS
        Retrieves metadata and mirrors a Git repository with download content in one step.

    .DESCRIPTION
        Combines Get-GitRepoFileMetadata and Sync-GitRepoFiles into a single command. Requires
        RepoUrl, BranchName, DownloadEndpoint, and DestinationRoot.

    .PARAMETER RepoUrl
        The URL of the remote Git repository.

    .PARAMETER BranchName
        The branch to sync (e.g., "main").

    .PARAMETER DownloadEndpoint
        The endpoint for download URLs (e.g., 'resolve').

    .PARAMETER DestinationRoot
        The local root folder to mirror content into (e.g., "C:\temp\test").

    .EXAMPLE
        Mirror-GitRepoWithDownloadContent \
          -RepoUrl "https://huggingface.co/microsoft/phi-4" \
          -BranchName "main" \
          -DownloadEndpoint "resolve" \
          -DestinationRoot "C:\temp\test"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage("PSUseApprovedVerbs","")]
    [CmdletBinding()]
    [alias('mirror-grwdc')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RepoUrl,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BranchName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DownloadEndpoint,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DestinationRoot
    )

    $metadata = Get-GitRepoFileMetadata -RepoUrl $RepoUrl -BranchName $BranchName -DownloadEndpoint $DownloadEndpoint
    Sync-GitRepoFiles -Metadata $metadata -DestinationRoot $DestinationRoot
}



#Mirror-GitRepoWithDownloadContent -RepoUrl "https://huggingface.co/microsoft/Phi-4-mini-instruct" -BranchName "main" -DownloadEndpoint "resolve" -DestinationRoot "C:\CustomizeAI\huggingface"
#Mirror-GitRepoWithDownloadContent -RepoUrl "https://huggingface.co/microsoft/phi-4" -BranchName "main" -DownloadEndpoint "resolve" -DestinationRoot "C:\temp\test"

#Sync-RemoteRepoFiles2 -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX" -BranchName "main" -LocalDestination "C:\temp\abaaasource" -PurgeExtraFiles
#Sync-RemoteRepoFiles3 -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX" -BranchName "feature/command" -LocalDestination "C:\temp\xBlackBytesBox.Manifested.GitX"
#Sync-RemoteRepoFiles3 -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX" -BranchName "feature/command"
#Sync-RemoteRepoFiles3 /?
#$x=1