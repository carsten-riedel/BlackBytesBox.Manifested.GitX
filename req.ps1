<#
.SYNOPSIS
    Writes a timestamped message in the host console with optional color.
.DESCRIPTION
    The Write-Info function formats and writes a message prefixed by the current time (HH:mm:ss).
    It supports custom foreground color and can be used for status updates or logging in scripts.
.PARAMETER Message
    The text to display in the console.
.PARAMETER Color
    The ConsoleColor to apply to the message. Defaults to Cyan.
.EXAMPLE
    Write-Info -Message 'Initialization complete.' -Color Green
#>
function Write-Info {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    # Format current time as hours:minutes:seconds
    $timestamp = (Get-Date).ToString('HH:mm:ss')

    # Output the timestamped message
    Write-Host "$timestamp  $Message" -ForegroundColor $Color
}

<#
.SYNOPSIS
Converts a Windows file path to a MSYS2-compatible Bash path.

.DESCRIPTION
Transforms a given Windows-style path (e.g., C:\folder\file) into the POSIX-style path
format used by MSYS2 Bash (e.g., /c/folder/file), enabling cross-environment compatibility.

.PARAMETER WindowsPath
The absolute Windows path to be converted (e.g., 'C:\Users\Projects').

.OUTPUTS
System.String. Returns the corresponding POSIX-style path string.

.EXAMPLE
Convert-ToMsysPath -WindowsPath "D:\Dev\Tools"
# Returns: /d/Dev/Tools

.NOTES
Throws an error if the input path does not match a valid drive-prefixed format.
#>
function Convert-ToMsysPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )
    # Replace backslashes with slashes
    $converted = $WindowsPath -replace '\\', '/'
    
    # Extract drive letter and path
    if ($converted -match '^([A-Za-z]):(.*)') {
        $drive = $matches[1].ToLower()
        $path = $matches[2]
        return "/$drive$path"
    }

    throw "Invalid Windows path format: $WindowsPath"
}

# Begin script
Write-Info -Message 'Starting script execution...'

try {
    Write-Info -Message 'Checking current execution policy...' -Color Yellow

    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    Write-Info -Message "CurrentUser policy is '$currentPolicy'." -Color Cyan

    $allowed = @('RemoteSigned', 'Unrestricted', 'Bypass')
    if ($allowed -contains $currentPolicy) {
        Write-Info -Message "Execution policy already allows script/module execution. No change needed." -Color Green
    }
    else {
        Write-Info -Message 'Setting execution policy to RemoteSigned to allow scripts/modules...' -Color Yellow
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Info -Message 'Execution policy updated to RemoteSigned. Scripts and modules can now run.' -Color Green
    }
}
catch {
    Write-Info -Message "ERROR: Failed to configure execution policy. $_" -Color Red
    exit 1
}


try {
    Write-Info -Message 'Checking installed NuGet Package Provider version...' -Color Yellow

    # Attempt to get the installed provider
    $provider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |  Sort-Object Version -Descending | Select-Object -First 1

    $minVersion = [Version]'2.8.5.201'
    if (-not $provider -or [Version]$provider.Version -lt $minVersion) {
        Write-Info -Message "Installing/Updating NuGet Package Provider to at least version $minVersion..." -Color Yellow
        Install-PackageProvider -Name NuGet -Force -MinimumVersion $minVersion -Scope CurrentUser | Out-Null
        Write-Info -Message 'NuGet Package Provider installed/updated successfully.' -Color Green
    }
    else {
        Write-Info -Message "NuGet Package Provider version $($provider.Version) is already >= $minVersion. No action needed." -Color Green
    }
}
catch {
    Write-Info -Message "ERROR: Failed to install or verify NuGet Package Provider. $_" -Color Red
    exit 1
}

try {
    Write-Info -Message 'Checking for PSGallery repository...' -Color Yellow

    # Try to get PSGallery; don’t stop on error so we can test for null
    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue

    if (-not $repo) {
        Write-Info -Message 'PSGallery not found. Registering default PowerShell Gallery as trusted...' -Color Yellow
        Register-PSRepository -Default -InstallationPolicy Trusted
        Write-Info -Message 'PSGallery registered and trusted.' -Color Green
    }
    elseif ($repo.InstallationPolicy -ne 'Trusted') {
        Write-Info -Message 'PSGallery found but not trusted. Setting policy to Trusted...' -Color Yellow
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Write-Info -Message 'PSGallery is now trusted.' -Color Green
    }
    else {
        Write-Info -Message 'PSGallery is already registered and trusted. No action needed.' -Color Green
    }
}
catch {
    Write-Info -Message "ERROR: Failed to verify/register/trust PSGallery. $_" -Color Red
    exit 1
}


try {
    Write-Info -Message 'Checking installed PowerShellGet module version...' -Color Yellow

    # Get the highest available PowerShellGet version
    $psg = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1

    $minVersion = [Version]'2.2.5'

    if (-not $psg -or [Version]$psg.Version -lt $minVersion) {
        Write-Info -Message "Updating PowerShellGet module to at least version $minVersion..." -Color Yellow
        Install-Module -Name PowerShellGet -MinimumVersion $minVersion -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
        Write-Info -Message 'PowerShellGet module updated successfully.' -Color Green
    }
    else {
        Write-Info -Message "PowerShellGet version $($psg.Version) is already ≥ $minVersion. No update needed." -Color Green
    }
}
catch {
    Write-Info -Message "ERROR: Failed to update PowerShellGet module. $_" -Color Red
    exit 1
}


try {
    Write-Info -Message 'Installing BlackBytesBox.Manifested.Initialize module...' -Color Yellow
    Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
    Write-Info -Message 'BlackBytesBox.Manifested.Initialize module installed successfully.' -Color Green
}
catch {
    Write-Info -Message "ERROR: Failed to install BlackBytesBox.Manifested.Initialize module. $_" -Color Red
    exit 1
}

try {
    Write-Info -Message 'Installing BlackBytesBox.Manifested.Git module...' -Color Yellow
    Install-Module -Name BlackBytesBox.Manifested.Git -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
    Write-Info -Message 'BlackBytesBox.Manifested.Git module installed successfully.' -Color Green
}
catch {
    Write-Info -Message "ERROR: Failed to install BlackBytesBox.Manifested.Git module. $_" -Color Red
    exit 1
}

# Detect OS and bail if not Windows
if (Test-IsWindows) {
    Write-Info -Message 'Detected Windows OS. Proceeding with MinGit installation...' -Color Cyan
}
else {
    Write-Info -Message 'Non-Windows OS detected. Exiting script.' -Color Red
    exit 1
}

# Only download MinGit if git.exe isn’t already on the PATH
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    # Set DownloadFolder to %LocalAppData%\Programs\Git
    $downloadFolder = Join-Path $env:LocalAppData 'Programs\Git'

    # Invoke the release‑downloader for MinGit x64 (excluding busybox builds)
    $result = Get-GitHubLatestRelease -RepoUrl 'https://github.com/git-for-windows/git' -Whitelist '*MinGit*','*64-bit*' -Blacklist '*busy*' -IncludeVersionFolder  -Extract -DownloadFolder $downloadFolder

    # Determine the MinGit root folder (subfolder named like "MinGit-2.49.0-64-bit")
    $minGitRoot = ($result | Select-Object -ExpandProperty Path | Select-Object -First 1)

    # Prefer mingw64\bin, else fall back to cmd
    $gitBin = Join-Path $minGitRoot 'mingw64\bin'
    if (-not (Test-Path $gitBin)) {
        $gitBin = Join-Path $minGitRoot 'cmd'
    }

    # Add to current session PATH if not already present
    if ($env:Path -notlike "*$gitBin*") {
        $env:Path = "$gitBin;$env:Path"
        Write-Info "$(Get-Date -Format 'HH:mm:ss')  Added $gitBin to current session PATH." -Color Green
    }

    # Persist to user profile PATH
    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($currentUserPath -notlike "*$gitBin*") {
        $newUserPath = "$gitBin;$currentUserPath"
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Info "$(Get-Date -Format 'HH:mm:ss')  Persisted $gitBin to user PATH." -Color Green
    }

    Write-Info "$(Get-Date -Format 'HH:mm:ss')  MinGit has been downloaded and configured." -Color Green
}
else {
    $gitPath = (Get-Command git.exe).Source
    Write-Info "$(Get-Date -Format 'HH:mm:ss')  Git is already available at $gitPath."
}


# Remove Windows Store shim from PATH if present
$storeShim = Join-Path $env:LocalAppData 'Microsoft\WindowsApps'

# Current session
if ($env:Path -like "*$storeShim*") {
    $env:Path = ($env:Path -split ';' | Where-Object { $_ -ne $storeShim }) -join ';'
    Write-Info -Message "Removed Windows Store shim from session PATH: $storeShim" -Color Yellow
}

# Persisted user PATH
$currentUserPath = [Environment]::GetEnvironmentVariable('Path','User')
if ($currentUserPath -like "*$storeShim*") {
    $newUserPath = ($currentUserPath -split ';' | Where-Object { $_ -ne $storeShim }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    Write-Info -Message "Removed Windows Store shim from user PATH: $storeShim" -Color Yellow
}

# --- Remove Windows Store shim, detect OS, install MinGit… [omitted for brevity] ---

# Check for python.exe / install pyenv-win
if (-not (Get-Command python.exe -ErrorAction SilentlyContinue) -and -not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Info -Message 'Python not detected. Cloning pyenv-win into %USERPROFILE%\.pyenv...' -Color Yellow

    # Validate Git clone operation idempotently
    $repoPath = "$env:USERPROFILE\.pyenv"
    if (Test-Path $repoPath) {
        Write-Info -Message "pyenv-win repo already exists at $repoPath; skipping clone." -Color Yellow
    } else {
        git clone https://github.com/pyenv-win/pyenv-win.git $repoPath
        if ($LASTEXITCODE -ne 0) {
            Write-Info -Message 'ERROR: git clone failed. Please check your Git configuration.' -Color Red
            exit 1
        }
        Write-Info -Message 'pyenv-win cloned successfully.' -Color Green
    }


    # --- BEGIN pyenv-win initialization ---

    # Define the root path
    $pyenvRoot = Join-Path $env:USERPROFILE '.pyenv\pyenv-win'

    # 1) Update current session env vars
    $env:PYENV       = $pyenvRoot
    $env:PYENV_HOME  = $pyenvRoot
    $env:PYENV_ROOT  = $pyenvRoot
    $env:Path        = "$pyenvRoot\bin;$pyenvRoot\shims;$env:Path"
    Write-Info -Message "Session variables set: PYENV, PYENV_HOME, PYENV_ROOT, and PATH updated." -Color Cyan

    # 2) Persist to user environment
    [Environment]::SetEnvironmentVariable('PYENV',      $pyenvRoot, 'User')
    [Environment]::SetEnvironmentVariable('PYENV_HOME', $pyenvRoot, 'User')
    [Environment]::SetEnvironmentVariable('PYENV_ROOT', $pyenvRoot, 'User')

    # Prepend to the persisted user PATH
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    if ($userPath -notlike "*$pyenvRoot*") {
        $newUserPath = "$pyenvRoot\bin;$pyenvRoot\shims;$userPath"
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Info -Message "Persisted pyenv-win paths to user PATH." -Color Cyan
    }

    # 3) Initialize and install Python versions
    Write-Info -Message 'Rehashing pyenv and installing Python 3.11.1…' -Color Yellow
    & pyenv rehash
    & pyenv install 3.11.1
    & pyenv global  3.11.1

    Write-Info -Message 'pyenv initialization complete. Installed versions:' -Color Green
    & pyenv versions

    # --- END pyenv-win initialization ---
}
else {
    # Determine which python source to report (compatible with PS 5)
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
    }
    $pyPath = $cmd.Source
    Write-Info -Message "Python is already available at $pyPath. Skipping pyenv-win setup." -Color Green
}


# Check for MSYS2 installation by looking for the 'msys64' folder
$programFolder = Join-Path $env:LocalAppData 'Programs'

# If the MSYS2 'msys64' folder doesn't exist, install
if (-not (Test-Path -Path (Join-Path $programFolder 'msys64') -PathType Container)) {
    Write-Info "MSYS2 not found. Starting installation..." -Color Yellow

    # Use the system temp directory for downloads and cleanup
    $tempRoot       = $env:TEMP
    $tempFolderName = [System.IO.Path]::GetRandomFileName()
    $tempFolder     = Join-Path $tempRoot $tempFolderName
    New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
    Write-Info "Created temporary folder: $tempFolder" -Color Green

    # Download the latest self-extracting installer from GitHub
    Write-Info "Downloading latest MSYS2 installer..." -Color Cyan
    $result = Get-GitHubLatestRelease `
        -RepoUrl 'https://github.com/msys2/msys2-installer' `
        -Whitelist '*latest.sfx.exe*' `
        -IncludeVersionFolder `
        -DownloadFolder   $tempFolder
    Write-Info "Download complete." -Color Green

    # Locate and run the installer in silent mode, output to ProgramFolder (recursive search)
    $installer = Get-ChildItem -Path $tempFolder -Filter '*.sfx.exe' -Recurse -File | Select-Object -First 1
    Write-Info "Running installer: $($installer.FullName)" -Color Cyan
    & $installer.FullName -y -o"$programFolder" | Out-Null
    Write-Info "MSYS2 installation finished." -Color Green

    # Clean up: remove installer and temporary folder
    Remove-Item -Path $installer.FullName -Force
    Write-Info "Removed installer executable." -Color Green
    Remove-Item -Path $tempFolder     -Recurse -Force
    Write-Info "Cleaned up temporary folder: $tempFolder" -Color Green
}
else {
    Write-Info "MSYS2 already installed (found '$($programFolder)\msys64')." -Color Cyan
}

$binOutput = "C:\llama"

if (-not (Test-Path -Path $binOutput -PathType Container)) {

    $msysInstallPath = Join-Path $env:LocalAppData 'Programs\msys64'
    $msysShellScript = """$msysInstallPath\msys2_shell.cmd"""
    $msysShellArgs = "-defterm -here -no-start -ucrt64 -shell bash -c"
    $fullShellCommand = "& $msysShellScript $msysShellArgs"`

    $bashCmdBaseInvoke = "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc git mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja"
    Write-Output "$fullShellCommand '$bashCmdBaseInvoke'"
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    $bashCmdBaseInvoke = "git clone --recurse-submodules https://github.com/ggerganov/llama.cpp.git ""`$HOME/llama.cpp"""
    Write-Output "$fullShellCommand '$bashCmdBaseInvoke'"
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    $binOutput = "C:\llama"
    $binOutputBash = Convert-ToMsysPath -WindowsPath $binOutput
    $bashCmdBaseInvoke = "cmake -S `$HOME/llama.cpp -B `$HOME/llama.cpp/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$binOutputBash -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_BUILD_SERVER=ON"
    Write-Output "$fullShellCommand '$bashCmdBaseInvoke'"
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    $bashCmdBaseInvoke = "cmake --build `$HOME/llama.cpp/build --config Release"
    Write-Output "$fullShellCommand '$bashCmdBaseInvoke'"
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    $bashCmdBaseInvoke = "cmake --install `$HOME/llama.cpp/build --config Release"
    Write-Output "$fullShellCommand '$bashCmdBaseInvoke'"
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

} else {
    Write-Info "Llama.cpp already present (found '$binOutput')." -Color Cyan
}



#Invoke-RestMethod -Uri https://raw.githubusercontent.com/carsten-riedel/BlackBytesBox.Manifested.GitX/refs/heads/main/req.ps1 | Invoke-Expression





# Ensure the current user can run local scripts that are remotely signed
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Updated second statement—now includes the complete switch for clarity
#Write-Host "Execution policy (-ExecutionPolicy RemoteSigned) set successfully."

#Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Scope CurrentUser | Out-Null
#Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
#Install-Module PowerShellGet -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
#Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery