# BlackBytesBox.Manifested.Git

A PowerShell module for retrieving and comparing essential Git repository information. This module offers commands to identify the repository's root directory, current branch, and repository name, as well as to compare remote and local file states.

## Features

- **Repository Information:**  
  - *Get-GitTopLevelDirectory*: Returns the root directory of the current Git repository.  
  - *Get-GitCurrentBranch*: Returns the current branch name or commit hash in a detached HEAD state.  
  - *Get-GitRepositoryName*: Extracts the repository name from the Git configuration.

- **Remote Repository Handling:**  
  - *Get-RemoteCommitId*: Retrieves the latest commit identifier for a given branch from a remote repository.  
  - *Get-RemoteRepoFileInfo*: Clones a remote repository (with metadata only) and gathers commit details (timestamps and messages) for each file.  
  - *Compare-LocalRemoteFileTimestamps*: Compares remote file timestamps with local file modification times to categorize files that require updates (RemoteNewer) versus those that are current (RemoteOlder).  
  - *Get-RemoteRepoFiles*: Checks out files from the remote repository that need updating based on the timestamp comparison.

## Prerequisites

- **Git** must be installed and available in your system's PATH.
- **PowerShell** version supporting module manifest features.

## Examples

Retrieve basic repository information:
```powershell
$result = Get-GitCurrentBranch
$result = Get-GitTopLevelDirectory
$result = Get-GitRepositoryName
$result = Get-RemoteCommitId -BranchName "main"
$nfo = Get-RemoteRepoFileInfo -BranchName "main" -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git"
$nfo.Files = Compare-LocalRemoteFileTimestamps -Files $nfo.Files -CompareDestination "C:\temp\test\BlackBytesBox.Manifested.GitX"
$files = Get-RemoteRepoFiles -BranchName $nfo.BranchName -RemoteRepo $nfo.RemoteRepo -Files $nfo.Files.RemoteNewer
