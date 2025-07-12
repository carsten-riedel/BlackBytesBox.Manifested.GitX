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
      %LOCALAPPDATA%\Write-LogInline\<FileAppName>\<yyyy-MM-dd>_PID<PID>.log

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
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()] [string]$Template,
        [object]$Params,
        [switch]$UseBackColor,
        [switch]$Overwrite,
        [switch]$InitialWrite,
        [string]$FileAppName,
        [switch]$ReturnJson
    )

    # Normalize any non-hashtable, non-array to a one‐item array
    if ($Params -isnot [hashtable] -and $Params -isnot [object[]]) {
        $Params = @($Params)
    }

    # Now enforce flatness on arrays
    if ($Params -is [object[]] -and ($Params |
    Where-Object { $_ -is [System.Collections.IEnumerable] -and -not ($_ -is [string]) }
    )) {
        throw "Parameter -Params array must be flat (no nested collections)."
    }

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
        $logPath = Join-Path $root "${date}_PID${PID}.log"
    }

    # Timestamp and render
    $timeEntry = Get-Date
    $timeStr   = $timeEntry.ToString('yyyy-MM-dd HH:mm:ss:ff')
    $plMatches = [regex]::Matches($Template, '{(?<name>\w+)}')
    $keys      = $plMatches | ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique
    $wasHash    = $Params -is [hashtable]
    $paramArray = @($Params)

    if (-not $wasHash -and $paramArray.Count -lt $keys.Count) {
        throw "Insufficient parameters: expected $($keys.Count), received $($paramArray.Count)"
    }

    $keys = @($keys)
    if ($wasHash) {
        $map = $Params
    } else {
        $map = @{}
        for ($i = 0; $i -lt $keys.Count; $i++) { $map[$keys[$i]] = $paramArray[$i] }  # CHANGED: use paramArray
    }

    # Fix: cast null to empty string, avoid boolean -or misuse
    $msg = $Template
    foreach ($k in $keys) {
        $escName = [regex]::Escape($k)
        $msg = $msg -replace "\{$escName\}", [string]$map[$k]
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
            'System.Version'  = 'Magenta'; 'Microsoft.PackageManagement.Internal.Utility.Versions.FourPartVersion' = 'Magenta'
            'Microsoft.PowerShell.ExecutionPolicy' = 'Magenta'
            'System.Management.Automation.ActionPreference' = 'Green'
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
      %LOCALAPPDATA%\Write-LogInline\<FileAppName>\<yyyy-MM-dd>_PID<PID>.log

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
function Write-LogInline2 {
    [CmdletBinding()]
    param(
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$Level,
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$MinLevel       = 'Information',
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$FileMinLevel  = 'Verbose',
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()] [string]$Template,
        [object]$Params,
        [switch]$UseBackColor,
        [switch]$Overwrite,
        [switch]$InitialWrite,
        [string]$Endpoint,
        [string]$ApiKey,
        [string]$LogSpace,
        [switch]$ReturnJson
    )

    # Normalize any non-hashtable, non-array to a one‐item array
    if ($Params -isnot [hashtable] -and $Params -isnot [object[]]) {
        $Params = @($Params)
    }

    # Now enforce flatness on arrays
    if ($Params -is [object[]] -and ($Params |
    Where-Object { $_ -is [System.Collections.IEnumerable] -and -not ($_ -is [string]) }
    )) {
        throw "Parameter -Params array must be flat (no nested collections)."
    }

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
    $writeToFile  = $caller -and ($levelValues[$Level] -ge $levelValues[$FileMinLevel])
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
        $root = Join-Path $base "Write-LogInline/$caller"

        if (-not (Test-Path $root)) { New-Item -Path $root -ItemType Directory | Out-Null }
        $date    = Get-Date -Format 'yyyy-MM-dd'
        $logPath = Join-Path $root "${date}_PID${PID}.log"
    }

    # Timestamp and render
    $timeEntry = Get-Date
    $timeStr   = $timeEntry.ToString('yyyy-MM-dd HH:mm:ss:ff')
    $plMatches = [regex]::Matches($Template, '{(?<name>\w+)}')
    $keys      = $plMatches | ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique
    $wasHash    = $Params -is [hashtable]
    $paramArray = @($Params)

    if (-not $wasHash -and $paramArray.Count -lt $keys.Count) {
        throw "Insufficient parameters: expected $($keys.Count), received $($paramArray.Count)"
    }

    $keys = @($keys)
    if ($wasHash) {
        $map = $Params
    } else {
        $map = @{}
        for ($i = 0; $i -lt $keys.Count; $i++) { $map[$keys[$i]] = $paramArray[$i] }  # CHANGED: use paramArray
    }

    # Fix: cast null to empty string, avoid boolean -or misuse
    $msg = $Template
    foreach ($k in $keys) {
        $escName = [regex]::Escape($k)
        $msg = $msg -replace "\{$escName\}", [string]$map[$k]
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
            'System.Version'  = 'Magenta'; 'Microsoft.PackageManagement.Internal.Utility.Versions.FourPartVersion' = 'Magenta'
            'Microsoft.PowerShell.ExecutionPolicy' = 'Magenta'
            'System.Management.Automation.ActionPreference' = 'Green'
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

    # Determinate Platform
    $platform    = if ($PSVersionTable.PSEdition -eq 'Core') {
                     if ($IsLinux) {'Linux'} elseif ($IsMacOS) {'macOS'} else {'Windows'}
                  } else {
                     'Windows'
                  }

    $edition    = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }

    # Determine script path, defaulting to "Console"
    if (-not [string]::IsNullOrEmpty($MyInvocation.PSCommandPath)) {
        $scriptPath = $MyInvocation.PSCommandPath
        $scriptName = Split-Path $scriptPath -Leaf
    }
    else {
        $scriptPath = 'Console'
        $scriptName = 'Console'
    }

    # Get the PowerShell call stack
    $callStack = Get-PSCallStack

    # If there's at least one caller above this function, grab it
    if ($callStack.Count -gt 1) {
        $callerFrame = $callStack[1]

        # Name of the function or script that invoked the logger
        $functionName = if ($callerFrame.FunctionName) {
            $callerFrame.FunctionName
        } else {
            'Script'
        }

        # File name (leaf) of the script/module, if any
        $scriptName = if ($callerFrame.ScriptName) {
            Split-Path $callerFrame.ScriptName -Leaf
        } else {
            'Console'
        }
    }
    else {
        # No caller (entered at console prompt)
        $functionName = 'Console'
        $scriptName   = 'Console'
    }

    # Return JSON
    $output = [PSCustomObject]@{
        EventId = [guid]::NewGuid().ToString()
        DateTime   = $timeEntry.ToString('o')     # "o" = round-trip yyyy-MM-ddTHH:mm:ss.fffffffK
        UtcTime = (Get-Date).ToUniversalTime().ToString('o')
        Level      = $Level
        Template   = $Template
        Message    = $msg
        Parameters = $map
        Platform = $platform
        PSVersion = $PSVersionTable.PSVersion.ToString()
        PSEdition = $edition
        PID        = $PID
        ProcName = (Get-Process -Id $PID).Name
        ScriptPath = $scriptPath
        ScriptName = $scriptName
        FunctionName = $functionName
        LineNumber = $MyInvocation.ScriptLineNumber
        Machine = [Environment]::MachineName
        Userdomain = [Environment]::UserDomainName
        User = [Environment]::UserName
    }

    # — new remote-post logic —
    if ($Endpoint -and $ApiKey -and $LogSpace) {
        $jsonBody = $output | ConvertTo-Json -Depth 6

        $headers = @{
            'X-API-Key'  = $ApiKey
            'X-Log-Space' = $LogSpace
        }

        try {
            Invoke-RestMethod `
            -Uri       $Endpoint `
            -Method    Post `
            -Headers   $headers `
            -Body      $jsonBody `
            -ContentType 'application/json' `
            -TimeoutSec  1
        }
        catch {
            # write to an "outbox" so you can retry later
            $outboxDir = Join-Path $env:LOCALAPPDATA "Write-LogInline\Outbox\$LogSpace"
            if (-not (Test-Path $outboxDir)) { New-Item -Path $outboxDir -ItemType Directory | Out-Null }
            $file = Join-Path $outboxDir ("{0:yyyyMMdd_HHmmss}_{1}.json" -f (Get-Date), $output.EventId)
            $jsonBody | Out-File -FilePath $file -Encoding UTF8
        }
    }
    # — end remote-post logic —

    # Return JSON only if requested
    if ($ReturnJson) {
        return $output | ConvertTo-Json -Depth 6
    }
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
    Ensures each specified directory is present in both the User and Process PATH scopes, resolving and normalizing paths.
.DESCRIPTION
    For each given PATH scope ('User' and 'Process'), adds any missing fully qualified directory paths.
    - Resolves each path to its absolute form and strips trailing backslashes.
    - Skips paths that cannot be resolved (emits a warning).
    - Prevents duplicates via case-insensitive comparison.
    - Provides verbose output when requested.
.PARAMETER Paths
    An array of directory paths to ensure are included in the User and Process PATH variables.
.OUTPUTS
    [PSCustomObject] with properties:
      - Success: [bool] Indicates if the specified paths were ensured (present or added).
      - Paths: [string[]] The list of specified paths that are now present in PATH.
.EXAMPLE
    # Ensure directories and capture the result
    $result = Add-ToUserPathIfMissing -Paths "C:\Tools\bin","C:\Dev\shims" -Verbose
    if ($result.Success) {
        Write-Host "Ensured paths: $($result.Paths -join ', ')"
    } else {
        Write-Host "No valid paths were provided to process."
    }
#>
function Add-ToUserPathIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Paths
    )

    # Resolve and normalize input paths once
    $resolvedPaths = $Paths | ForEach-Object {
        try {
            (Resolve-Path $_ -ErrorAction Stop).ProviderPath.TrimEnd('\')
        } catch {
            Write-Warning "Cannot resolve path: $_"
            continue
        }
    } | Select-Object -Unique

    if (-not $resolvedPaths) {
        Write-Verbose "No valid paths to process."
        return [PSCustomObject]@{ Success = $false; Paths = @() }
    }

    foreach ($scope in 'User','Process') {
        try {
            # Read and normalize existing PATH entries
            $currentPaths = [Environment]::GetEnvironmentVariable('Path', $scope)
            $normalizedCurrent = $currentPaths -split ';' | ForEach-Object {
                try { (Resolve-Path $_ -ErrorAction Stop).ProviderPath.TrimEnd('\') } catch { }
            } | Where-Object { $_ } | Select-Object -Unique
        } catch {
            Write-Error "Failed to read $scope PATH: $_"
            continue
        }

        # Determine which paths are missing
        $missing = $resolvedPaths | Where-Object { $_ -notin $normalizedCurrent }
        if (-not $missing) {
            Write-Verbose "[$scope] No new paths to add."
            continue
        }
        $missing = @($missing)

        # Prepend missing entries and update environment variable
        $newValue = ($missing + ($currentPaths -split ';')) -join ';'
        try {
            [Environment]::SetEnvironmentVariable('Path', $newValue, $scope)
            Write-Verbose "[$scope] Added paths: $($missing -join ', ')"
        } catch {
            Write-Error "Failed to update $scope PATH: $_"
        }
    }

    # Return ensuring result: all requested paths are now present
    return [PSCustomObject]@{ Success = $true; Paths = $resolvedPaths }
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

<#
.SYNOPSIS
    Sets and normalizes the USER Path environment variable for User scope only, with support for environment variable expansion.

.DESCRIPTION
    Splits the User PATH into tokens; removes blank entries; expands any embedded environment variables;
    trims trailing '\\' characters; resolves each token to its real-cased, full path (or falls back to GetFullPath);
    removes duplicate entries; optionally sorts them; and writes the cleaned list back to the User environment scope.

.PARAMETER Scope
    The environment scope to update: 'User', 'Process', or 'Both' (default).

.PARAMETER Sort
    If specified, sorts the final entries alphabetically.

.PARAMETER RemoveNonexistent
    If specified, any PATH token that does not resolve to an existing file system entry
    will be omitted from the final list.

.PARAMETER RemoveEmptyDirs
    If specified, any PATH token that resolves to an existing directory but contains no files or subdirectories
    will be omitted from the final list.

.PARAMETER NoReturn
    If specified, the function will not output the cleaned PATH list; it will run silently.

.OUTPUTS
    System.String[]
    The list of path entries written back to the specified scope(s), unless -NoReturn is used.

.EXAMPLE
    # Normalize only your User PATH, preserving the original order
    Update-UserEnvironmentPath -Scope User

.EXAMPLE
    # Normalize, remove dead and empty directories
    Update-UserEnvironmentPath -Sort -RemoveEmptyDirs -RemoveNonexistent -NoReturn -Verbose

.EXAMPLE
    # Normalize without returning the list
    Update-UserEnvironmentPath -Scope User -NoReturn
#>
function Update-UserEnvironmentPath {

    [CmdletBinding()]
    param(
        [ValidateSet('User','Process','Both')]
        [string]$Scope = 'Both',

        [switch]$Sort,

        [switch]$RemoveNonexistent,

        [switch]$RemoveEmptyDirs,

        [switch]$NoReturn
    )

    # Determine target scopes based on parameter
    $targets = if ($Scope -eq 'Both') { 'User','Process' } else { $Scope }

    # Store original and computed lists
    $originalPaths = @{}
    $computedLists  = @{}

    try {
        foreach ($t in $targets) {
            $raw = [Environment]::GetEnvironmentVariable('Path', $t)
            $originalPaths[$t] = $raw

            if (-not $raw) {
                Write-Verbose "[$t] Original PATH is empty; nothing to normalize."
                $computedLists[$t] = @()
                continue
            }

            Write-Verbose "[$t] Loaded $($raw -split ';').Count raw tokens."

            # Split into tokens, count blanks removed
            $allTokens       = $raw -split ';'
            $tokens          = $allTokens | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $blankRemoved    = $allTokens.Count - $tokens.Count

            # Initialize stats
            $purgedCount         = 0
            $emptyDirCount       = 0
            $slashTrimCount      = 0
            $casingChangeCount   = 0

            # Expand any embedded environment variables and normalize each entry
            $normalized = foreach ($entry in $tokens) {
                $expanded = [Environment]::ExpandEnvironmentVariables($entry)
                $trimmed  = $expanded.TrimEnd('\')
                if ($expanded -ne $trimmed) { $slashTrimCount++ }

                # Remove non-existent
                if ($RemoveNonexistent -and -not (Test-Path -LiteralPath $trimmed -PathType Any)) {
                    Write-Verbose "Skipping non-existent entry: $trimmed"
                    $purgedCount++
                    continue
                }

                # Remove empty dirs
                if ($RemoveEmptyDirs -and (Test-Path -LiteralPath $trimmed -PathType Container)) {
                    $items = Get-ChildItem -LiteralPath $trimmed -Force -ErrorAction SilentlyContinue
                    if (-not $items) {
                        Write-Verbose "Skipping empty directory: $trimmed"
                        $emptyDirCount++
                        continue
                    }
                }

                # Resolve path casing or fallback
                if (Test-Path -LiteralPath $trimmed -ErrorAction SilentlyContinue) {
                    $resolved = (Get-Item -LiteralPath $trimmed).FullName.TrimEnd('\')
                    if ($resolved -ne $trimmed) { $casingChangeCount++ }
                } else {
                    $resolved = [IO.Path]::GetFullPath($trimmed).TrimEnd('\')
                }
                $resolved
            }

            # Summary of actions
            Write-Verbose "[$t] Removed $blankRemoved empty entries, purged $purgedCount missing entries, removed $emptyDirCount empty dirs, trimmed $slashTrimCount trailing backslashes, corrected casing on $casingChangeCount entries."

            # Remove duplicates and optionally sort
            $unique = $normalized | Select-Object -Unique
            if ($Sort) { $unique = $unique | Sort-Object -Descending}

            Write-Verbose "[$t] Computed $($unique.Count) cleaned entries."
            $computedLists[$t] = $unique
        }
    } catch {
        Write-Warning "Error during normalization: $_. No changes applied."
        return
    }

    # Backup and apply changes
    try {
        foreach ($t in $targets) {
            [Environment]::SetEnvironmentVariable('Backup_PATH', $originalPaths[$t], $t)
            Write-Verbose "[$t] Backup saved to 'Backup_PATH'."
        }

        foreach ($t in $targets) {
            [Environment]::SetEnvironmentVariable('Path', ($computedLists[$t] -join ';'), $t)
            Write-Verbose "[$t] Applied cleaned PATH with $($computedLists[$t].Count) entries."
        }

        Write-Verbose "All scopes updated successfully."
    } catch {
        Write-Warning "Error during commit: $_. Attempting rollback."
        foreach ($t in $targets) {
            try {
                [Environment]::SetEnvironmentVariable('Path', $originalPaths[$t], $t)
                Write-Verbose "[$t] Rolled back to original PATH."
            } catch {
                Write-Error "[$t] Rollback failed: $_"
            }
        }
    }

    if (-not $NoReturn) {
        return $computedLists
    }
}

Update-UserEnvironmentPath -Sort -RemoveNonexistent -RemoveEmptyDirs -NoReturn
#Write-LogInline2 -Level Information -Template "Script execution has started.{foo} {baZ}" -Params "bar", 42  @WriteLogInlineDefaults

#Clear-Host

$WriteLogInlineDefaults = @{
    FileMinLevel  = 'Error'
    MinLevel      = 'Information'
    UseBackColor  = $false
    Overwrite     = $false
    FileAppName   = 'req.ps1'
    ReturnJson    = $true
}

$WriteLogInlineDefaults2 = @{
    FileMinLevel  = 'Error'
    MinLevel      = 'Information'
    UseBackColor  = $false
    Overwrite     = $false
    ReturnJson    = $true
    Endpoint   = 'https://localhost:8080/api/logs'
    ApiKey     = 'your_api_key_here'
    LogSpace     = 'foo'

}


# Begin script
Write-LogInline -Level Information -Template "Script execution has started." @WriteLogInlineDefaults

Write-LogInline2 -Level Error -Template "Script execution has started." @WriteLogInlineDefaults2

try {
    Write-LogInline -Level Information -Template "Checking current execution policy..." @WriteLogInlineDefaults

    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    Write-LogInline -Level Information -Template "CurrentUser policy is '{currentPolicy}'." -Params $currentPolicy @WriteLogInlineDefaults

    $allowed = @('RemoteSigned', 'Unrestricted', 'Bypass')
    if ($allowed -contains $currentPolicy) {
        Write-LogInline -Level Information -Template "Execution policy is already set appropriately. Skipping changes." @WriteLogInlineDefaults
    }
    else {
        Write-LogInline -Level Information -Template "Setting execution policy to {RemoteSigned} to allow scripts/modules..." -Params 'RemoteSigned' @WriteLogInlineDefaults
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-LogInline -Level Information -Template "Execution policy updated to {RemoteSigned}. Scripts and modules can now run." -Params 'RemoteSigned' @WriteLogInlineDefaults
    }
}
catch {
    Write-LogInline -Level Error -Template "Failed to configure execution policy. $_" @WriteLogInlineDefaults
    exit 1
}

$originalProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
Write-LogInline -Level Information -Template 'ProgressPreference temporarily set to {ProgressPreference}' -Params 'SilentlyContinue' @WriteLogInlineDefaults

try {
    Write-LogInline -Level Information -Template 'Checking installed NuGet Package Provider version...' @WriteLogInlineDefaults

    # Attempt to get the installed provider
    $provider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1

    $minVersion = [Version]'2.8.5.201'
    if (-not $provider -or [Version]$provider.Version -lt $minVersion) {
        Write-LogInline -Level Information -Template "Installing/Updating NuGet Package Provider to at least version {0}..." -Params $minVersion @WriteLogInlineDefaults
        Install-PackageProvider -Name NuGet -Force -MinimumVersion $minVersion -Scope CurrentUser | Out-Null
        Write-LogInline -Level Information -Template 'NuGet Package Provider installed/updated successfully.' @WriteLogInlineDefaults
    }
    else {
        Write-LogInline -Level Information -Template "NuGet Package Provider version {0} is already >= {1}. No action needed." -Params @($provider.Version, $minVersion) @WriteLogInlineDefaults
    }
}
catch {
    Write-LogInline -Level Error -Template "Failed to install or verify NuGet Package Provider. $_" @WriteLogInlineDefaults
    exit 1
}


try {
    Write-LogInline -Level Information -Template 'Checking for PSGallery repository...' @WriteLogInlineDefaults

    # Try to get PSGallery; don’t stop on error so we can test for null
    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue

    if (-not $repo) {
        Write-LogInline -Level Information -Template 'PSGallery not found. Registering default PowerShell Gallery as trusted...' @WriteLogInlineDefaults
        Register-PSRepository -Default -InstallationPolicy Trusted
        Write-LogInline -Level Information -Template 'PSGallery registered and trusted.' @WriteLogInlineDefaults
    }
    elseif ($repo.InstallationPolicy -ne 'Trusted') {
        Write-LogInline -Level Information -Template 'PSGallery found but not trusted. Setting policy to Trusted...' @WriteLogInlineDefaults
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Write-LogInline -Level Information -Template 'PSGallery is now trusted.' @WriteLogInlineDefaults
    }
    else {
        Write-LogInline -Level Information -Template 'PSGallery is already registered and trusted. No action needed.' @WriteLogInlineDefaults
    }
}
catch {
    Write-LogInline -Level Error -Template "Failed to verify/register/trust PSGallery. $_" @WriteLogInlineDefaults
    exit 1
}


try {
    Write-LogInline -Level Information -Template 'Checking installed PowerShellGet module version...' @WriteLogInlineDefaults

    # Get the highest available PowerShellGet version
    $psg = Get-Module -ListAvailable -Name PowerShellGet |
           Sort-Object Version -Descending |
           Select-Object -First 1

    $minVersion = [Version]'2.2.5'

    if (-not $psg -or [Version]$psg.Version -lt $minVersion) {
        Write-LogInline -Level Information -Template 'Updating PowerShellGet module to at least version {0}...' -Params $minVersion @WriteLogInlineDefaults
        Install-Module -Name PowerShellGet -MinimumVersion $minVersion -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
        Write-LogInline -Level Information -Template 'PowerShellGet module updated successfully.' @WriteLogInlineDefaults
    }
    else {
        Write-LogInline -Level Information -Template 'PowerShellGet version {0} is already ≥ {1}. No update needed.' -Params @($psg.Version, $minVersion) @WriteLogInlineDefaults
    }
}
catch {
    Write-LogInline -Level Error -Template 'Failed to update PowerShellGet module. {0}' -Params $_ @WriteLogInlineDefaults
    exit 1
}

try {
    Write-LogInline -Level Information -Template 'Installing {0} module...' -Params "BlackBytesBox.Manifested.Initialize" @WriteLogInlineDefaults
    Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
    Write-LogInline -Level Information -Template '{0} module installed successfully.' -Params "BlackBytesBox.Manifested.Initialize" @WriteLogInlineDefaults
}
catch {
    Write-LogInline -Level Error -Template 'Failed to install BlackBytesBox.Manifested.Initialize module. {0}' -Params $_ @WriteLogInlineDefaults
    exit 1
}

try {
    Write-LogInline -Level Information -Template 'Installing {0} module...' -Params "BlackBytesBox.Manifested.Git" @WriteLogInlineDefaults
    Install-Module -Name BlackBytesBox.Manifested.Git -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
    Write-LogInline -Level Information -Template '{0} module installed successfully.' -Params "BlackBytesBox.Manifested.Git" @WriteLogInlineDefaults
}
catch {
    Write-LogInline -Level Error -Template 'Failed to install BlackBytesBox.Manifested.Git module. {0}' -Params $_ @WriteLogInlineDefaults
    exit 1
}


$ProgressPreference = $originalProgressPreference
Write-LogInline -Level Information -Template 'ProgressPreference restored to {ProgressPreference}' -Params $originalProgressPreference @WriteLogInlineDefaults


# Define your cleanup block as before
$cleanupScript = {
    Remove-OldModuleVersions -Name 'BlackBytesBox.Manifested.Initialize'
    Remove-OldModuleVersions -Name 'BlackBytesBox.Manifested.Git'
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
    $outputLines | ForEach-Object { Write-LogInline -Level Information -Template "$_" @WriteLogInlineDefaults }
}
if ($errorOutput) {
    Write-LogInline -Level Error -Template "Errors: " @WriteLogInlineDefaults
    $errorLines = $errorOutput.Split("`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' }
    $errorLines | ForEach-Object { Write-LogInline -Level Error -Template "$_" @WriteLogInlineDefaults }
}




# Detect OS and bail if not Windows
if (Test-IsWindows) {
    Write-LogInline -Level Information -Template 'Detected Windows OS. Proceeding with installation...' @WriteLogInlineDefaults
}
else {
    Write-LogInline -Level Warning -Template 'Script is not supported on non-Windows OS. Exiting.' @WriteLogInlineDefaults
    exit 1
}

Write-LogInline -Level Information -Template 'Verifying Git installation status...' @WriteLogInlineDefaults

# Only download MinGit if git.exe isn’t already on the PATH
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    # Set DownloadFolder to %LocalAppData%\Programs\Git
    $downloadFolder = Join-Path $env:LocalAppData 'Programs\MinGit64'

    Write-LogInline -Level Information -Template 'Downloading and extracting MinGit 64 bit ...' -Params $downloadFolder @WriteLogInlineDefaults

    # Invoke the release‑downloader for MinGit x64 (excluding busybox builds)
    $result = Get-GitHubLatestRelease -RepoUrl 'https://github.com/git-for-windows/git' -Whitelist '*MinGit*','*64-bit*' -Blacklist '*busy*' -IncludeVersionFolder -Extract -DownloadFolder $downloadFolder

    # Determine the MinGit root folder (subfolder named like "MinGit-2.49.0-64-bit")
    $minGitRoot = ($result | Select-Object -ExpandProperty Path | Select-Object -First 1)

    $minGitBin = Join-Path $minGitRoot 'mingw64\bin'
    
    $retval = Add-ToUserPathIfMissing -Paths $minGitBin
    foreach ($added in $retval.Paths)
    {
        Write-LogInline -Level Information -Template 'Added {added} to user PATH.' -Params $added @WriteLogInlineDefaults
    }

    Write-LogInline -Level Information -Template 'MinGit has been downloaded and configured.' @WriteLogInlineDefaults
}
else {
    $gitPath = (Get-Command git.exe).Source
    Write-LogInline -Level Information -Template 'Git is already available at {gitpath}' -Params $gitPath @WriteLogInlineDefaults
}


# Remove Windows Store shim from PATH if present
$storeShim = Join-Path $env:LocalAppData 'Microsoft\WindowsApps'

# Current session
if ($env:Path -like "*$storeShim*") {
    $env:Path = ($env:Path -split ';' | Where-Object { $_ -ne $storeShim }) -join ';'
    Write-LogInline -Level Information -Template 'Removed Windows Store shim from current session PATH: {storeShim}' -Params $storeShim @WriteLogInlineDefaults
}

# Persisted user PATH
$currentUserPath = [Environment]::GetEnvironmentVariable('Path','User')
if ($currentUserPath -like "*$storeShim*") {
    $newUserPath = ($currentUserPath -split ';' | Where-Object { $_ -ne $storeShim }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    Write-LogInline -Level Information -Template 'Removed Windows Store shim from user profile PATH: {storeShim}' -Params $storeShim @WriteLogInlineDefaults
}

Write-LogInline -Level Information -Template 'Verifying Python installation status...' @WriteLogInlineDefaults

# Check for python.exe / install pyenv-win
if (-not (Get-Command python.exe -ErrorAction SilentlyContinue) -and -not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-LogInline -Level Information -Template 'Python not detected. Cloning pyenv-win into %USERPROFILE%\.pyenv...' @WriteLogInlineDefaults

    # Validate Git clone operation idempotently
    $repoPath = "$env:USERPROFILE\.pyenv"
    if (Test-Path $repoPath) {
        Write-LogInline -Level Warning -Template 'pyenv-win repo already exists at {repoPath}; skipping clone.' -Params $repoPath @WriteLogInlineDefaults
    } else {
        git clone https://github.com/pyenv-win/pyenv-win.git $repoPath
        if ($LASTEXITCODE -ne 0) {
            Write-LogInline -Level Error -Template 'Git clone failed. Please check your Git configuration.' @WriteLogInlineDefaults
            exit 1
        }
        Write-LogInline -Level Information -Template 'pyenv-win cloned successfully.' @WriteLogInlineDefaults
    }

    # --- BEGIN pyenv-win initialization ---
    $pyenvRoot = Join-Path $env:USERPROFILE '.pyenv\pyenv-win'

    Add-ToUserEnvarIfMissing -Name 'PYENV' -Value $pyenvRoot -Overwrite
    Add-ToUserEnvarIfMissing -Name 'PYENV_HOME' -Value $pyenvRoot -Overwrite
    Add-ToUserEnvarIfMissing -Name 'PYENV_ROOT' -Value $pyenvRoot -Overwrite
    
    $retval = Add-ToUserPathIfMissing -Paths "$pyenvRoot\bin", "$pyenvRoot"
    foreach ($added in $retval.Paths)
    {
        Write-LogInline -Level Information -Template 'Added {added} to user PATH.' -Params $added @WriteLogInlineDefaults
    }

    # 3) Initialize and install Python versions
    Write-LogInline -Level Information -Template 'Rehashing pyenv and installing Python 3.11.1…' @WriteLogInlineDefaults

    & pyenv rehash
    & pyenv install 3.11.9
    & pyenv global  3.11.9

    $retval = Add-ToUserPathIfMissing -Paths "$pyenvRoot\shims"
    foreach ($added in $retval.Paths)
    {
        Write-LogInline -Level Information -Template 'Added {added} to user PATH.' -Params $added @WriteLogInlineDefaults
    }

    Write-LogInline -Level Information -Template 'pyenv initialization complete. Installed versions:' @WriteLogInlineDefaults
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
    Write-LogInline -Level Information -Template 'Python is already available at {pyPath}. Skipping pyenv-win setup.' -Params $pyPath @WriteLogInlineDefaults
}


Write-LogInline -Level Information -Template 'Verifying MSYS2 installation status...' @WriteLogInlineDefaults

# Check for MSYS2 installation by looking for the 'msys64' folder
$programFolder = Join-Path $env:LocalAppData 'Programs'
$programFolderMsys2 = Join-Path $programFolder 'msys64'

# If the MSYS2 'msys64' folder doesn't exist, install
if (-not (Test-Path -Path $programFolderMsys2 -PathType Container)) {
    Write-LogInline -Level Warning -Template 'MSYS2 not found. Starting installation...' @WriteLogInlineDefaults

    # Use the system temp directory for downloads and cleanup
    $tempRoot       = $env:TEMP
    $tempFolderName = [System.IO.Path]::GetRandomFileName()
    $tempFolder     = Join-Path $tempRoot $tempFolderName
    New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
    Write-LogInline -Level Information -Template 'Created temporary folder: {tempFolder}' -Params $tempFolder @WriteLogInlineDefaults

    # Download the latest self-extracting installer from GitHub
    Write-LogInline -Level Information -Template 'Downloading latest MSYS2 installer... {folder}' -Params $tempFolder @WriteLogInlineDefaults
    $result = Get-GitHubLatestRelease `
        -RepoUrl 'https://github.com/msys2/msys2-installer' `
        -Whitelist '*latest.sfx.exe*' `
        -IncludeVersionFolder `
        -DownloadFolder $tempFolder
    Write-LogInline -Level Information -Template 'Download complete.' @WriteLogInlineDefaults

    # Locate and run the installer in silent mode, output to ProgramFolder (recursive search)
    $installer = Get-ChildItem -Path $tempFolder -Filter '*.sfx.exe' -Recurse -File | Select-Object -First 1
    Write-LogInline -Level Information -Template 'Running installer: {installerPath}' -Params $installer.FullName @WriteLogInlineDefaults
    & $installer.FullName -y -o"$programFolder" | Out-Null
    Write-LogInline -Level Information -Template 'MSYS2 installation finished.' @WriteLogInlineDefaults

    # Clean up: remove installer and temporary folder
    Remove-Item -Path $installer.FullName -Force
    Write-LogInline -Level Information -Template 'Removed installer executable.' @WriteLogInlineDefaults
    Remove-Item -Path $tempFolder -Recurse -Force
    Write-LogInline -Level Information -Template 'Cleaned up temporary folder: {tempFolder}' -Params $tempFolder @WriteLogInlineDefaults
}
else {
    Write-LogInline -Level Information -Template 'MSYS2 already installed (found {programFolderMsys2}).' -Params $programFolderMsys2 @WriteLogInlineDefaults
}

Write-LogInline -Level Information -Template "Verifying llama.cpp installation status..." @WriteLogInlineDefaults

# Check for llama.cpp installation by looking for the 'llama.cpp' folder
$programFolderLlamaCpp = Join-Path $env:LocalAppData 'Programs\llama.cpp'

if (-not (Test-Path -Path $programFolderLlamaCpp -PathType Container)) {

    $msysInstallPath = Join-Path $env:LocalAppData 'Programs\msys64'
    $msysShellScript = """$msysInstallPath\msys2_shell.cmd"""
    $msysShellArgs = "-defterm -here -no-start -ucrt64 -shell bash -c"
    $fullShellCommand = "& $msysShellScript $msysShellArgs"

    Write-LogInline -Level Information -Template "First msys call initalize scripts have to run..."  @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "echo 'First msys call initalize scripts have to run...'"
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke"  @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke' | Out-Null"
   
    Write-LogInline -Level Information -Template "Installing dependencies via pacman..."  @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "pacman -S --needed --noconfirm --noprogressbar mingw-w64-ucrt-x86_64-gcc git mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja"
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke"  @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-LogInline -Level Information -Template "Cloning llama.cpp repository..." @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "git clone --recurse-submodules https://github.com/ggerganov/llama.cpp.git ""`$HOME/llama.cpp"""
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke"  @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    $binOutputBash = Convert-ToMsysPath -WindowsPath $programFolderLlamaCpp

    Write-LogInline -Level Information -Template "Configuring build with CMake..." @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "cmake -S `$HOME/llama.cpp -B `$HOME/llama.cpp/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$binOutputBash -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_BUILD_SERVER=ON"
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke" @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-LogInline -Level Information -Template "Building llama.cpp..." @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "cmake --build `$HOME/llama.cpp/build --config Release"
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke" @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-LogInline -Level Information -Template "Installing llama.cpp..." @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "cmake --install `$HOME/llama.cpp/build --config Release"
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke" @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Write-LogInline -Level Information -Template "Copying missing dlls to llama.cpp..." @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "cp /ucrt64/bin/*.dll ""$binOutputBash/bin/"""
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke" @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"

    Add-ToUserPathIfMissing -Paths "$programFolderLlamaCpp\bin"

} else {
    Write-LogInline -Level Information -Template "Llama.cpp already present (found {programFolderLlamaCpp})." -Params $programFolderLlamaCpp @WriteLogInlineDefaults
}


## additional check for llama cloned. for convert script.

<#
$msysClonePath = Join-Path $env:LocalAppData "Programs\msys64\home\$($env:Username)\llama.cpp"
if (-not (Test-Path -Path $msysClonePath -PathType Container)) {
    
    $msysInstallPath = Join-Path $env:LocalAppData 'Programs\msys64'
    $msysShellScript = """$msysInstallPath\msys2_shell.cmd"""
    $msysShellArgs = "-defterm -here -no-start -ucrt64 -shell bash -c"
    $fullShellCommand = "& $msysShellScript $msysShellArgs"

    Write-LogInline -Level Information -Template "Cloning llama.cpp repository..." @WriteLogInlineDefaults
    $bashCmdBaseInvoke = "git clone --recurse-submodules https://github.com/ggerganov/llama.cpp.git ""`$HOME/llama.cpp"""
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke"  @WriteLogInlineDefaults
    Write-LogInline -Level Information -Template "Executing: $bashCmdBaseInvoke"  @WriteLogInlineDefaults
    Invoke-Expression "$fullShellCommand '$bashCmdBaseInvoke'"
    
} else {
    Write-LogInline -Level Information -Template 'Virtual environment already exists at {virtualEnvPath}.' -Params $virtualEnvPath @WriteLogInlineDefaults
}
#>


Write-LogInline -Level Information -Template 'Verifying Python installation status...' @WriteLogInlineDefaults

if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-LogInline -Level Information -Template 'Found Python. Proceeding with environment setup...' @WriteLogInlineDefaults

    # Define variables
    $pythonCommand      = "python"
    $pythonModuleSwitch = "-m"
    $virtualEnvPath     = Join-Path $env:Userprofile 'PythonVirtualEnvironment'
    $venvExecutable     = Join-Path $virtualEnvPath 'Scripts\python.exe'

    # Function to invoke python module commands
    function Invoke-VenvCommand {
        param(
            [string]$ModuleArgs
        )
        Invoke-Expression "& $venvExecutable $pythonModuleSwitch $ModuleArgs"
    }


    
    Write-LogInline -Level Information -Template 'Checking for virtual environment at {virtualEnvPath}...' -Params $virtualEnvPath @WriteLogInlineDefaults
    if (-not (Test-Path -Path $virtualEnvPath -PathType Container)) {
        Write-LogInline -Level Information -Template 'Creating virtual environment at {virtualEnvPath}...' -Params $virtualEnvPath @WriteLogInlineDefaults
        & $pythonCommand $pythonModuleSwitch venv "$virtualEnvPath"
        Write-LogInline -Level Information -Template "$pythonCommand $pythonModuleSwitch venv $virtualEnvPath" -Params $virtualEnvPath @WriteLogInlineDefaults
    } else {
        Write-LogInline -Level Information -Template 'Virtual environment already exists at {virtualEnvPath}.' -Params $virtualEnvPath @WriteLogInlineDefaults
    }

    # Upgrade pip & tooling
    Write-LogInline -Level Information -Template 'Upgrading pip, wheel, and setuptools...' @WriteLogInlineDefaults
    Invoke-VenvCommand "pip install --upgrade pip wheel setuptools"

    # Install core Python packages
    Write-LogInline -Level Information -Template 'Installing core packages: torch, transformers, peft, datasets, safetensors...' @WriteLogInlineDefaults
    Invoke-VenvCommand "pip install torch transformers peft datasets safetensors"

    # Install conversion requirements if available
    $conversionReqFile = Join-Path $programFolderMsys2 "home\$($env:Username)\llama.cpp\requirements\requirements-convert_hf_to_gguf.txt"
    Write-LogInline -Level Information -Template 'Checking for conversion requirements file at {conversionReqFile}...' -Params $conversionReqFile @WriteLogInlineDefaults
    if (Test-Path -Path $conversionReqFile) {
        Write-LogInline -Level Information -Template 'Installing conversion requirements from {conversionReqFile}...' -Params $conversionReqFile @WriteLogInlineDefaults
        Invoke-VenvCommand "pip install --upgrade -r `"$conversionReqFile`""
    } else {
        Write-LogInline -Level Warning -Template 'No conversion requirements file found. Skipping.' @WriteLogInlineDefaults
    }

} else {
    Write-LogInline -Level Error -Template "'python' not found in PATH. Please install Python or adjust the script." @WriteLogInlineDefaults
}

# Print manual activation instruction
$activateScript = Join-Path $virtualEnvPath 'Scripts\Activate.ps1'
Write-LogInline -Level Information -Template "To activate this virtual environment later, run:" @WriteLogInlineDefaults
Write-LogInline -Level Information -Template "    & '$activateScript'" @WriteLogInlineDefaults

Write-LogInline -Level Information -Template "https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen3-0.6B" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen3-0.6B' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen3-1.7B" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen3-1.7B' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen3-4B" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen3-4B' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen3-8B" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen3-8B' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'

Write-LogInline -Level Information -Template "https://huggingface.co/Qwen/Qwen3-14B" @WriteLogInlineDefaults
Mirror-GitRepoWithDownloadContent -RepoUrl 'https://huggingface.co/Qwen/Qwen3-14B' -BranchName 'main' -DownloadEndpoint 'resolve' -DestinationRoot 'C:\HuggingfaceModels' -Filter 'onnx/*','runs/*'




Write-LogInline -Level Information -Template 'Verifying Python installation status...' @WriteLogInlineDefaults

$pythoncmd = Get-Command python -ErrorAction SilentlyContinue
$convertcmd = Get-Command convert_hf_to_gguf.py -ErrorAction SilentlyContinue
if ($pythoncmd -and $convertcmd) {
    Write-LogInline -Level Information -Template 'Found Python. Proceeding with environment setup...' @WriteLogInlineDefaults

    $convertHfToGgufPath = (Get-Command convert_hf_to_gguf.py -ErrorAction SilentlyContinue).Source
    # Define variables
    $pythonCommand      = "python"
    $pythonModuleSwitch = "-m"
    $virtualEnvPath     = Join-Path $env:Userprofile 'PythonVirtualEnvironment'
    $venvExecutable     = Join-Path $virtualEnvPath 'Scripts\python.exe'

    # Function to invoke python module commands
    function Invoke-VenvCommand {
        param(
            [string]$ModuleArgs
        )
        Invoke-Expression "& $venvExecutable $ModuleArgs"
        Write-Host "& $venvExecutable $ModuleArgs"
    }

    # Destination directory: ensure it exists
    $destDir = 'C:\HuggingfaceModels\ConvertedSafeTensors'
    if (-not (Test-Path -Path $destDir -PathType Container)) {
        Write-LogInline -Level Information -Template 'Creating destination directory at {destDir}...' -Params $destDir @WriteLogInlineDefaults
        New-Item -Path $destDir -ItemType Directory | Out-Null
    }

    # Virtual environment creation

    Write-LogInline -Level Information -Template 'Checking for virtual environment at {virtualEnvPath}...' -Params $virtualEnvPath @WriteLogInlineDefaults
    if (Test-Path -Path $virtualEnvPath -PathType Container) {
        if (Test-Path -Path 'C:\HuggingfaceModels\HuggingFaceTB\SmolLM2-135M-Instruct' -PathType Container) {
            Write-LogInline -Level Information -Template 'Model is downloaded and ready for convert.' @WriteLogInlineDefaults
            $gguflatest = Join-Path $programFolderMsys2 "home\$($env:Username)\llama.cpp\gguf-py"
            Invoke-VenvCommand "$pythonModuleSwitch pip install -e ""$gguflatest"""
            Invoke-VenvCommand "$convertHfToGgufPath C:\HuggingfaceModels\HuggingFaceTB\SmolLM2-135M-Instruct --outfile C:\HuggingfaceModels\ConvertedSafeTensors\SmolLM2-135M-Instruct.gguf"
            Invoke-VenvCommand "$convertHfToGgufPath C:\HuggingfaceModels\agentica-org\DeepCoder-14B-Preview --outfile C:\HuggingfaceModels\ConvertedSafeTensors\DeepCoder-14B-Preview.gguf"
        } else {
            Write-LogInline -Level Error -Template "" -Params $virtualEnvPath @WriteLogInlineDefaults
        }
    } else {
        Write-LogInline -Level Error -Template 'Virtual environment not exists at {virtualEnvPath}.' -Params $virtualEnvPath @WriteLogInlineDefaults
    }
    

    # Upgrade pip & tooling


} else {
    Write-LogInline -Level Error -Template "'python' not found in PATH. Please install Python or adjust the script." @WriteLogInlineDefaults
}

# Check for Microsoft Visual C++ Redistributable 2015-2019 (x64) via core DLL version
# This method inspects vcruntime140.dll in System32 for presence and correct minimum version

# Desired minimum version (from 14.29.30156 onwards)
$minVersion = [Version]'14.29.30156.0'

# Path to 64-bit runtime DLL
$dllPath = Join-Path $env:SystemRoot 'System32\vcruntime140.dll'

if (Test-Path $dllPath) {
    try {
        $fileVersionInfo = (Get-Item $dllPath).VersionInfo #powershell version info
        $installedVersion = [Version]$fileVersionInfo.FileVersionRaw # Get the raw version string
        if ($installedVersion -ge $minVersion) {
            Write-LogInline -Level Information -Template "Runtime DLL found: {dllPath} (version {installedVersion})" -Params "$dllPath","$installedVersion" @WriteLogInlineDefaults
        } else {
            Write-LogInline -Level Warning -Template "Runtime version too low: {installedVersion} (< {minVersion})" -Params "$installedVersion","$minVersion" @WriteLogInlineDefaults
        }
    } catch {
        Write-LogInline -Level Error -Template "Error reading version info from {dllPath}: {0}" -Params "$dllPath", "$_.Exception.Message" @WriteLogInlineDefaults
    }
} else {
    Write-LogInline -Level Error -Template "Missing runtime DLL: {dllPath}" -Params $dllPath @WriteLogInlineDefaults
}

Write-LogInline -Level Information -Template "Script {Script} has finished processing." -Params "req.ps1" @WriteLogInlineDefaults

#Invoke-RestMethod -Uri https://raw.githubusercontent.com/carsten-riedel/BlackBytesBox.Manifested.GitX/refs/heads/main/req.ps1 | Invoke-Expression



