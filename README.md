# BlackBytesBox.Manifested.Git

A PowerShell module for retrieving, mirroring, and comparing essential Git repository information. This module offers commands to identify the repository's root directory, current branch, and repository name, as well as to mirror a repo (including download‑content) or synchronize updated files between remote and local.

## Features

- **Repository Information:**  
  - *Get-GitTopLevelDirectory*: Returns the root directory of the current Git repository.  
  - *Get-GitCurrentBranch*: Returns the current branch name or commit hash in a detached HEAD state.  
  - *Get-GitRepositoryName*: Extracts the repository name from the Git configuration.

- **Remote Repository Handling:**  
  - **Mirror-GitRepoWithDownloadContent**  
    - **Synopsis:**  
      Clone or mirror a Git repository (metadata only) and then fetch any large or binary content via direct web requests—bypassing slow Git LFS pulls—into a local directory, and keep it up‑to‑date on the specified branch.  
    - **Parameters:**  
      - `-RepoUrl` (string, **mandatory**): URL of the repository to mirror.  
      - `-BranchName` (string, default: `main`): Branch to mirror and stay in sync with.  
      - `-DownloadEndpoint` (string, **mandatory**): URL pattern or API endpoint for fetching large files, LFS assets, release bundles, or other downloadable content.  
      - `-DestinationRoot` (string, **mandatory**): Local path where the mirror and downloaded assets will be stored.  
    - **Behavior & Qualities:**  
      1. **Metadata‑only clone**: Uses `--mirror --no-checkout` (or equivalent) to fetch only refs and tree metadata—no file blobs.  
      2. **Web‑request download**: Enumerates required assets (LFS pointers, release archives, etc.) and retrieves them via HTTP(S) calls, avoiding slow `git lfs pull`.  
      3. **Branch‑driven sync**: Always targets the given branch; can be rerun to pull new commits and new assets, so your local mirror stays current.  
      4. **Performance**: Significantly faster for large repositories with LFS or binary releases.  
      5. **Consistency**: Ensures the working files in `DestinationRoot` exactly reflect the remote branch state plus any extra assets.  

  - **Sync-RemoteRepoFiles**: Automatically synchronize updated files from the remote repository with a specified local destination. Retrieves remote file metadata, compares timestamps, checks out updated files, and copies them locally.  
  - *Get-RemoteCommitId*: Retrieves the latest commit identifier for a given branch from a remote repository.  
  - *Get-RemoteRepoFileInfo*: Clones a remote repository (metadata only) and gathers commit details (timestamps, messages, and file sizes) for each file.  
  - *Compare-LocalRemoteFileTimestamps*: Compares remote file timestamps with local file modification times to determine which files require updates (`RemoteNewer`) and which are up‑to‑date (`RemoteOlder`).  
  - *Get-RemoteRepoFiles*: Performs a sparse checkout (metadata clone + selective blob fetch) of files from the remote repository that need updating based on the timestamp comparison.  

## Prerequisites

- **Git** must be installed and available in your system's PATH.  
- **PowerShell** version 5.0 or higher (recommended) to support module manifest features and advanced scripting capabilities.  

## Examples

```powershell
# Mirror a repo (metadata-only + webrequest download) into C:\temp\test,
# and keep it synced with the 'main' branch:
Mirror-GitRepoWithDownloadContent `
  -RepoUrl "https://huggingface.co/microsoft/Phi-4-mini-instruct" `
  -BranchName "main" `
  -DownloadEndpoint "resolve" `
  -DestinationRoot "C:\temp\huggingface"

Mirror-GitRepoWithDownloadContent `
  -RepoUrl "'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct'" `
  -BranchName "main" `
  -DownloadEndpoint "resolve" `
  -DestinationRoot "C:\temp\huggingface" `
  -Filter 'onnx/*','runs/*'
  

# Retrieve Git repository information
Get-GitCurrentBranch
Get-GitTopLevelDirectory
Get-GitRepositoryName

# Get latest commit ID from remote
$commitId = Get-RemoteCommitId `
  -BranchName "main" `
  -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git"

# Sync only updated files from remote to local
$nfo = Get-RemoteRepoFileInfo `
  -BranchName "main" `
  -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git"

$nfo.Files = Compare-LocalRemoteFileTimestamps `
  -Files $nfo.Files `
  -CompareDestination "C:\temp\test\BlackBytesBox.Manifested.GitX"

$files = Get-RemoteRepoFiles `
  -BranchName $nfo.BranchName `
  -RemoteRepo $nfo.RemoteRepo `
  -Files $nfo.Files.RemoteNewer

# Full sync of automatically detected changes
Sync-RemoteRepoFiles `
  -RemoteRepo "https://github.com/carsten-riedel/BlackBytesBox.Manifested.GitX.git" `
  -BranchName "main" `
  -LocalDestination "C:\temp\BlackBytesBox.Manifested.GitX"
