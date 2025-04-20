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






# Ensure the current user can run local scripts that are remotely signed
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Updated second statement—now includes the complete switch for clarity
#Write-Host "Execution policy (-ExecutionPolicy RemoteSigned) set successfully."

#Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Scope CurrentUser | Out-Null
#Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
#Install-Module PowerShellGet -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
#Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery