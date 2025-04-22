<#
.SYNOPSIS
    Writes a timestamped, color‑coded inline log entry to the console, optionally appends to a daily log file, and optionally returns log details as JSON.

.DESCRIPTION
    Formats messages with a high-precision timestamp, log-level abbreviation, and caller identifier. Color-codes console output by severity, can overwrite the previous line, and can append to a per-process daily log file.
    Use -ReturnJson to emit a JSON representation of the log details instead of returning nothing.

.PARAMETER Level
    The log level. Valid values: Verbose, Debug, Information, Warning, Error, Critical.

.PARAMETER MinLevel
    Minimum level to write to the console. Messages below this level are suppressed. Default: Information.

.PARAMETER FileMinLevel
    Minimum level to append to the log file. Messages below this level are skipped. Default: Verbose.

.PARAMETER Template
    The message template, using placeholders like {Name}.

.PARAMETER Params
    Values for each placeholder in Template. Either a hashtable or an ordered object array.

.PARAMETER UseBackColor
    Switch to enable background coloring in the console.

.PARAMETER Overwrite
     Switch to overwrite the previous console entry rather than writing a new line.

.PARAMETER InitialWrite
    Switch to output an initial blank line instead of attempting to overwrite on the first call when using -Overwrite.

.PARAMETER FileAppName
    When set, enables file logging under:
      %LOCALAPPDATA%\Write-LogInline\<FileAppName>\<yyyy-MM-dd>_<PID>.log

.PARAMETER ReturnJson
    Switch to return the log details as a JSON-formatted string; otherwise, no output.

.EXAMPLE
    # Write a green "Hello, World!" message to the console
    Write-LogInline -Level Information `
                   -Template "{greeting}, {user}!" `
                   -Params @{ greeting = "Hello"; user = "World" }

.EXAMPLE
    # Using defaults plus -ReturnJson
    $WriteLogInlineDefaults = @{
        FileMinLevel  = 'Verbose'
        MinLevel      = 'Information'
        UseBackColor  = $false
        Overwrite     = $true
        FileAppName   = 'testing'
        ReturnJson    = $false
    }

    Write-LogInline -Level Verbose `
                   -Template "{hello}-{world} number {num} at {time}!" `
                   -Params "Hello","World",1,1.2 `
                   @WriteLogInlineDefaults

.NOTES
    Requires PowerShell 5.0 or later.
#>
function Write-LogInline {
    [CmdletBinding()]
    param(
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$Level,
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$MinLevel       = 'Information',
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$FileMinLevel  = 'Verbose',
        [string]$Template,
        [object]$Params,
        [switch]$UseBackColor,
        [switch]$Overwrite,
        [switch]$InitialWrite,
        [string]$FileAppName,
        [switch]$ReturnJson
    )

    # ANSI escape
    $esc = [char]27
    if (-not $script:WLI_Caller) {
        $script:WLI_Caller = if ($MyInvocation.PSCommandPath) { Split-Path -Leaf $MyInvocation.PSCommandPath } else { 'Console' }
    }
    $caller = $script:WLI_Caller

    # Level maps
    $levelValues = @{ Verbose=0; Debug=1; Information=2; Warning=3; Error=4; Critical=5 }
    $abbrMap      = @{ Verbose='VRB'; Debug='DBG'; Information='INF'; Warning='WRN'; Error='ERR'; Critical='CRT' }

    $writeConsole = $levelValues[$Level] -ge $levelValues[$MinLevel]
    $writeToFile  = $FileAppName -and ($levelValues[$Level] -ge $levelValues[$FileMinLevel])
    if (-not ($writeConsole -or $writeToFile)) { return }

    # File path init
    if ($writeToFile) {
        $os = [int][System.Environment]::OSVersion.Platform
        switch ($os) {
            2 { $base = $env:LOCALAPPDATA } # Win32NT
            4 { $base = Join-Path $env:HOME ".local/share" } # Unix
            6 { $base = Join-Path $env:HOME ".local/share" } # MacOSX
            default { throw "Unsupported OS platform: $os" }
        }
        $root = Join-Path $base "Write-LogInline/$FileAppName"

        if (-not (Test-Path $root)) { New-Item -Path $root -ItemType Directory | Out-Null }
        $date    = Get-Date -Format 'yyyy-MM-dd'
        $logPath = Join-Path $root "${date}_${PID}.log"
    }

    # Timestamp and render
    $Params = @($Params)
    $timeEntry = Get-Date
    $timeStr   = $timeEntry.ToString('yyyy-MM-dd HH:mm:ss:fff')
    $plMatches = [regex]::Matches($Template, '{(?<name>\w+)}')
    $keys      = $plMatches | ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique
    $keys = @($keys)
    if ($Params -is [hashtable]) {
        $map = @($Params)
    } else {
        $map = @{}
        for ($i = 0; $i -lt $keys.Count; $i++) { $map[$keys[$i]] = $Params[$i] }
    }

    # Fix: cast null to empty string, avoid boolean -or misuse
    $msg = $Template
    foreach ($k in $keys) {
        $msg = $msg -replace "\{$k\}", [string]$map[$k]
    }
    $rawLine = "[$timeStr $($abbrMap[$Level])][$caller] $msg"

    # Write to file
    if ($writeToFile) { $rawLine | Out-File -FilePath $logPath -Append -Encoding UTF8 }

    # Console output
    if ($writeConsole) {
        if ($InitialWrite) {
            # Initial invocation: write a blank line instead of overwriting
            Write-Host ""
        }
        if ($Overwrite) {
            for ($i = 0; $i -lt $script:WLI_LastLines; $i++) {
                Write-Host -NoNewline ($esc + '[1A' + "`r" + $esc + '[K')
            }
        }
        Write-Host -NoNewline ($esc + '[?25l')

        # Color maps
        $levelMap = @{
            Verbose     = @{ Abbrev='VRB'; Fore='DarkGray' }
            Debug       = @{ Abbrev='DBG'; Fore='Cyan'     }
            Information = @{ Abbrev='INF'; Fore='Green'    }
            Warning     = @{ Abbrev='WRN'; Fore='Yellow'   }
            Error       = @{ Abbrev='ERR'; Fore='Red'      }
            Critical    = @{ Abbrev='CRT'; Fore='White'; Back='DarkRed' }
        }
        $typeColorMap = @{
            'System.String'   = 'Green';   'System.DateTime' = 'Yellow'
            'System.Int32'    = 'Cyan';    'System.Int64'     = 'Cyan'
            'System.Double'   = 'Blue';    'System.Decimal'   = 'Blue'
            'System.Boolean'  = 'Magenta'; 'Default'          = 'White'
        }
        $staticFore = 'White'; $staticBack = 'Black'
        function Write-Colored { param($Text,$Fore,$Back) if ($UseBackColor -and $Back) { Write-Host -NoNewline $Text -ForegroundColor $Fore -BackgroundColor $Back } else { Write-Host -NoNewline $Text -ForegroundColor $Fore } }

        # Header
        $entry = $levelMap[$Level]
        $tag   = $entry.Abbrev
        if ($entry.ContainsKey('Back')) {
            $lvlBack = $entry.Back
        } elseif ($UseBackColor) {
            $lvlBack = $staticBack
        } else {
            $lvlBack = $null
        }
        Write-Colored '[' $staticFore $staticBack; Write-Colored $timeStr $staticFore $staticBack; Write-Colored ' ' $staticFore $staticBack
        if ($lvlBack) { Write-Host -NoNewline $tag -ForegroundColor $entry.Fore -BackgroundColor $lvlBack } else { Write-Host -NoNewline $tag -ForegroundColor $entry.Fore }
        Write-Colored '] [' $staticFore $staticBack; Write-Colored $caller $staticFore $staticBack; Write-Colored '] ' $staticFore $staticBack

        # Message parts
        $pos = 0
        foreach ($m in $plMatches) {
            if ($m.Index -gt $pos) {
                Write-Colored $Template.Substring($pos, $m.Index - $pos) $staticFore $staticBack
            }
            $val = $map[$m.Groups['name'].Value]
            $t   = $val.GetType().FullName

            if ($typeColorMap.ContainsKey($t)) {
                $f = $typeColorMap[$t]
            } else {
                $f = $typeColorMap['Default']
            }

            if ($UseBackColor) {
                $b = $staticBack
            } else {
                $b = $null
            }

            Write-Colored $val $f $b
            $pos = $m.Index + $m.Length
        }

        if ($pos -lt $Template.Length) {
            if ($UseBackColor) {
                $b = $staticBack
            } else {
                $b = $null
            }
            Write-Colored $Template.Substring($pos) $staticFore $b
        }

        Write-Host ''
        Write-Host -NoNewline ($esc + '[?25h')

        try {
            $width = $Host.UI.RawUI.WindowSize.Width
        } catch {
            $width = 80
        }

        $script:WLI_LastLines = [math]::Ceiling($rawLine.Length / ($width - 1))
    }

    # Return JSON
    $output = [PSCustomObject]@{
        DateTime   = $timeEntry
        PID        = $PID
        Level      = $Level
        Template   = $Template
        Message    = $msg
        Parameters = $map
    }

    # Return JSON only if requested
    if ($ReturnJson) {
        return $output | ConvertTo-Json -Depth 5
    }
}

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

<#
.SYNOPSIS
    Ensures each directory path is prepended to the user and session PATH environment variable if not already present.
.DESCRIPTION
    Adds one or more fully qualified directory paths to the user and current session PATH if not already present.
    This function is general-purpose and does not assume any subfolder structure.
.PARAMETER Paths
    An array of fully qualified directory paths to ensure are included in the user and session PATH.
.EXAMPLE
    Add-ToUserPathIfMissing -Paths "C:\Tools\bin", "C:\Dev\shims"
#>
function Add-ToUserPathIfMissing {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $sessionPath = [Environment]::GetEnvironmentVariable('Path','Process')
    $missingPaths = $Paths | Where-Object { $userPath -notlike "*$_*" }

    if ($missingPaths) {
        $newUserPath = ($missingPaths -join ';') + ';' + $userPath
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')

        $newSessionPath = ($missingPaths -join ';') + ';' + $sessionPath
        [Environment]::SetEnvironmentVariable('Path', $newSessionPath, 'Process')
    }
}

<#
.SYNOPSIS
    Adds or updates a user environment variable with optional overwrite control.
.DESCRIPTION
    Sets the specified environment variable at the User level and in the current session.
    If Overwrite is not set, the variable is only added if it does not already exist.
.PARAMETER Name
    The name of the environment variable to set.
.PARAMETER Value
    The value to assign to the environment variable.
.PARAMETER Overwrite
    If specified, overwrites the existing variable value.
.EXAMPLE
    Add-ToUserEnvarIfMissing -Name "MY_VAR" -Value "SomeValue" -Overwrite
#>
function Add-ToUserEnvarIfMissing {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [switch]$Overwrite
    )

    $userExisting = [Environment]::GetEnvironmentVariable($Name, 'User')
    $procExisting = [Environment]::GetEnvironmentVariable($Name, 'Process')

    if ($Overwrite -or [string]::IsNullOrEmpty($userExisting)) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    }

    if ($Overwrite -or [string]::IsNullOrEmpty($procExisting)) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
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


# Define your cleanup block as before
$cleanupScript = {
    Remove-OldModuleVersions -ModuleName 'BlackBytesBox.Manifested.Initialize'
    Remove-OldModuleVersions -ModuleName 'BlackBytesBox.Manifested.Git'
}

# Prepare PowerShell process start info for in-memory output capture
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $($cleanupScript.ToString())"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

# Start the process and capture output
$process = [System.Diagnostics.Process]::Start($psi)
$output = $process.StandardOutput.ReadToEnd()
$errorOutput = $process.StandardError.ReadToEnd()
$process.WaitForExit()

# Display captured output and errors in the current session
if ($output) {
    $outputLines = $output.Split("`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' }
    $outputLines | ForEach-Object { Write-Info -Message $_ -Color Yellow }
}
if ($errorOutput) {
    Write-Host -Message "Errors:" -Color Red
    $errorLines = $errorOutput.Split("`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' }
    $errorLines | ForEach-Object { Write-Info -Message $_ -Color Red }
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
$programFolderMsys2 = Join-Path $programFolder 'msys64'

# If the MSYS2 'msys64' folder doesn't exist, install
if (-not (Test-Path -Path $programFolderMsys2 -PathType Container)) {
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
    Write-Info "MSYS2 already installed (found '$($programFolderMsys2)')." -Color Cyan
}

Write-Info "Checking for llama installation..." -Color Yellow

# Check for llama.cpp installation by looking for the 'llama.cpp' folder
$programFolderLlamaCpp = Join-Path $env:LocalAppData 'Programs\llama.cpp'

if (-not (Test-Path -Path $programFolderLlamaCpp -PathType Container)) {

    $msysInstallPath = Join-Path $env:LocalAppData 'Programs\msys64'
    $msysShellScript = """$msysInstallPath\msys2_shell.cmd"""
    $msysShellArgs = "-defterm -here -no-start -ucrt64 -shell bash -c"
    $fullShellCommand = "& $msysShellScript $msysShellArgs"

    Write-Info "Installing dependencies via pacman..." -Color Cyan
    $bashCmdBaseInvoke = "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc git mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja"
    Write-Info "Executing: $bashCmdBaseInvoke" -Color Gray
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-Info "Cloning llama.cpp repository..." -Color Cyan
    $bashCmdBaseInvoke = "git clone --recurse-submodules https://github.com/ggerganov/llama.cpp.git ""`$HOME/llama.cpp"""
    Write-Info "Executing: $bashCmdBaseInvoke" -Color Gray
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    $binOutputBash = Convert-ToMsysPath -WindowsPath $programFolderLlamaCpp

    Write-Info "Configuring build with CMake..." -Color Cyan
    $bashCmdBaseInvoke = "cmake -S `$HOME/llama.cpp -B `$HOME/llama.cpp/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$binOutputBash -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_BUILD_SERVER=ON"
    Write-Info "Executing: $bashCmdBaseInvoke" -Color Gray
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-Info "Building llama.cpp..." -Color Cyan
    $bashCmdBaseInvoke = "cmake --build `$HOME/llama.cpp/build --config Release"
    Write-Info "Executing: $bashCmdBaseInvoke" -Color Gray
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-Info "Installing llama.cpp..." -Color Cyan
    $bashCmdBaseInvoke = "cmake --install `$HOME/llama.cpp/build --config Release"
    Write-Info "Executing: $bashCmdBaseInvoke" -Color Gray
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-Info "Copying missing dlls to llama.cpp..." -Color Cyan
    $bashCmdBaseInvoke = "cp /ucrt64/bin/*.dll ""$binOutputBash/bin/"""
    Write-Info "Executing: $bashCmdBaseInvoke" -Color Gray
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Add-ToUserPathIfMissing -Paths "$programFolderLlamaCpp\bin"

} else {
    Write-Info "Llama.cpp already present (found '$programFolderLlamaCpp')." -Color Green
}

Write-Info "[INFO] Checking for Python executable in PATH..." -Color Cyan
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Info "[OK] Found Python: 'python'. Proceeding with environment setup..." -Color Green

    # Define variables
    $pythonCommand      = "python"
    $pythonModuleSwitch = "-m"
    $virtualEnvPath     = "C:\PythonVirtualEnv"
    $venvExecutable     = Join-Path $virtualEnvPath 'Scripts\python.exe'

    # Function to invoke python module commands
    function Invoke-VenvCommand {
        param(
            [string]$ModuleArgs
        )
        Invoke-Expression "& $venvExecutable $pythonModuleSwitch $ModuleArgs"
    }

    # Virtual environment creation
    Write-Info "[INFO] Checking for virtual environment at '$virtualEnvPath'..." -Color Cyan
    if (-not (Test-Path -Path $virtualEnvPath -PathType Container)) {
        Write-Info "[INFO] Creating virtual environment at '$virtualEnvPath'..." -Color Cyan
        & $pythonCommand $pythonModuleSwitch venv "$virtualEnvPath"
    } else {
        Write-Info "[OK] Virtual environment already exists at '$virtualEnvPath'." -Color Green
    }

    # Upgrade pip & tooling
    Write-Info "[INFO] Upgrading pip, wheel, and setuptools..." -Color Cyan
    Invoke-VenvCommand "pip install --upgrade pip wheel setuptools"

    # Install core Python packages
    Write-Info "[INFO] Installing core packages: torch, transformers, peft, datasets, safetensors..." -Color Cyan
    Invoke-VenvCommand "pip install torch transformers peft datasets safetensors"

    # Install conversion requirements if available
    $conversionReqFile = Join-Path $programFolderMsys2 "home\$($env:Username)\llama.cpp\requirements\requirements-convert_hf_to_gguf.txt"
    Write-Info "[INFO] Checking for conversion requirements file at '$conversionReqFile'..." -Color Cyan
    if (Test-Path -Path $conversionReqFile) {
        Write-Info "[INFO] Installing conversion requirements from '$conversionReqFile'..." -Color Cyan
        Invoke-VenvCommand "pip install --upgrade -r `"$conversionReqFile`""
    } else {
        Write-Info "[WARN] No conversion requirements file found; skipping." -Color Yellow
    }

} else {
    Write-Info "[ERROR] 'python' not found in PATH. Please install Python or adjust the script." -Color Red
}

# Print manual activation instruction
$activateScript = Join-Path $virtualEnvPath 'Scripts\Activate.ps1'
Write-Info "[INFO] To activate this virtual environment later, run:" -Color Cyan
Write-Info "    & '$activateScript'" -Color Gray

Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'
#Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'
#Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/microsoft/Phi-4-mini-instruct' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels'

$WriteLogInlineDefaults = @{
    FileMinLevel  = 'Error'
    MinLevel      = 'Information'
    UseBackColor  = $false
    Overwrite     = $false
    FileAppName   = 'req.ps1'
    ReturnJson    = $false
}

Write-LogInline -Level Information -Template "Finished processing {Script} !" -Params "req.ps1" @WriteLogInlineDefaults

#Invoke-RestMethod -Uri https://raw.githubusercontent.com/carsten-riedel/BlackBytesBox.Manifested.GitX/refs/heads/main/req.ps1 | Invoke-Expression



