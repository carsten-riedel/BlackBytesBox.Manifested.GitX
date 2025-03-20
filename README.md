# BlackBytesBox.Manifested.Git

A PowerShell module for retrieving and comparing essential Git repository information. This module offers commands to identify the repository's root directory, current branch, and repository name, as well as to compare remote and local file states and synchronize updated files.

## Features

- **Repository Information:**  
  - *Get-GitTopLevelDirectory*: Returns the root directory of the current Git repository.  
  - *Get-GitCurrentBranch*: Returns the current branch name or commit hash in a detached HEAD state.  
  - *Get-GitRepositoryName*: Extracts the repository name from the Git configuration.

- **Remote Repository Handling:**
  - **Sync-RemoteRepoFiles**: Combines the above functionality to automatically synchronize updated files from the remote repository with a specified local destination. This command retrieves remote file information, compares file timestamps, checks out updated files, and copies them to the local destination.
  - *Get-RemoteCommitId*: Retrieves the latest commit identifier for a given branch from a remote repository.  
  - *Get-RemoteRepoFileInfo*: Clones a remote repository (with metadata only) and gathers commit details (timestamps, messages, and file sizes) for each file.  
  - *Compare-LocalRemoteFileTimestamps*: Compares remote file timestamps with local file modification times to determine which files require updates (RemoteNewer) and which are up-to-date (RemoteOlder).  
  - *Get-RemoteRepoFiles*: Performs a sparse checkout of files from the remote repository that need updating based on the timestamp comparison.  


## Prerequisites

- **Git** must be installed and available in your system's PATH.
- **PowerShell** version 5.0 or higher (recommended) to support module manifest features and advanced scripting capabilities.

## Examples

Retrieve basic repository information:
```powershell
$result = Get-GitCurrentBranch
$result = Get-GitTopLevelDirectory
$result = Get-GitRepositoryName
$result = Get-RemoteCommitId -BranchName "main"

Sync-RemoteRepoFiles -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX" -BranchName "main" -LocalDestination "C:\temp\BlackBytesBox.Manifested.GitX"

$nfo = Get-RemoteRepoFileInfo -BranchName "main" -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git"
$nfo.Files = Compare-LocalRemoteFileTimestamps -Files $nfo.Files -CompareDestination "C:\temp\test\BlackBytesBox.Manifested.GitX"
$files = Get-RemoteRepoFiles -BranchName $nfo.BranchName -RemoteRepo $nfo.RemoteRepo -Files $nfo.Files.RemoteNewer
```