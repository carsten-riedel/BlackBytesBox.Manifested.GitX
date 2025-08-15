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

.PARAMETER MinLevelFile
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
        MinLevelFile  = 'Verbose'
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
function Out-Log {
    [CmdletBinding()]
    param(
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')][string]$Level,
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical','None')][string]$MinLevelConsole = 'Information',
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical','None')][string]$MinLevelFile = 'Information',
        [ValidateSet('Verbose','Debug','Information','Warning','Error','Critical','None')][string]$MinLevelPost = 'Information',
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()] [string]$Template,
        [object]$Params,
        [switch]$ConsoleOverwriteLastLine,
        [switch]$InitialWrite,
        [string]$StaticForeColor = $null,
        [string]$StaticBackColor = $null,
        [string]$Endpoint,
        [string]$ApiKey,
        [string]$LogSpace,
        [switch]$ReturnJson,
        [switch]$SuppressConsoleCaller,
        [switch]$ConsoleUseShortDate
    )

    $fileLogPath = "Out-Log"

    if (-not $script:WLI_AlreadySetColors -and (
        -not [string]::IsNullOrEmpty($StaticForeColor) -or
        -not [string]::IsNullOrEmpty($StaticBackColor))) { # test for already set once
        $e = [char]27
        $map = @{ Black='#000000'; DarkBlue='#00008B'; DarkGreen='#006400'; DarkCyan='#008B8B'; DarkRed='#8B0000'; DarkMagenta='#8B008B'; DarkYellow='#B8860B'; Gray='#BFBFBF'; DarkGray='#808080'; Blue='#0000FF'; Green='#008000'; Cyan='#00FFFF'; Red='#FF0000'; Magenta='#FF00FF'; Yellow='#FFFF00'; White='#FFFFFF' }

        # Resolve colors → hex
        $foreHex = $null
        if (-not [string]::IsNullOrEmpty($StaticForeColor)) {
            $foreHex = if ($StaticForeColor -match '^#?[0-9A-Fa-f]{6}$') {
                if ($StaticForeColor[0] -eq '#') { $StaticForeColor } else { "#$StaticForeColor" }
            } elseif ($map.ContainsKey($StaticForeColor)) {
                $map[$StaticForeColor]
            } else { '#FFFFFF' }
        }

        $backHex = $null
        if (-not [string]::IsNullOrEmpty($StaticBackColor)) {
            $backHex = if ($StaticBackColor -match '^#?[0-9A-Fa-f]{6}$') {
                if ($StaticBackColor[0] -eq '#') { $StaticBackColor } else { "#$StaticBackColor" }
            } elseif ($map.ContainsKey($StaticBackColor)) {
                $map[$StaticBackColor]
            } else { '#000000' }
        }

        if ($env:WT_SESSION) {
            if ($foreHex) { Write-Host -NoNewline "$e]10;$foreHex`a" } # default foreground
            if ($backHex) { Write-Host -NoNewline "$e]11;$backHex`a" } # default background
            #Write-Host "$e[2J$e[H"                                      # clear + home to repaint
        } else {
            try {
                if ($StaticForeColor) { [Console]::ForegroundColor = [Enum]::Parse([ConsoleColor], $StaticForeColor, $true) }
                if ($StaticBackColor) { [Console]::BackgroundColor = [Enum]::Parse([ConsoleColor], $StaticBackColor, $true) }
                [Console]::Clear()
            } catch { }
        }
        $script:WLI_AlreadySetColors = $true
    }

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
    $levelValues = @{ Verbose=0; Debug=1; Information=2; Warning=3; Error=4; Critical=5; None=6 }
    $abbrMap      = @{ Verbose='VRB'; Debug='DBG'; Information='INF'; Warning='WRN'; Error='ERR'; Critical='CRT'; None='NON' }

    $writeConsole = $levelValues[$Level] -ge $levelValues[$MinLevelConsole]
    $writeToFile  = $caller -and ($levelValues[$Level] -ge $levelValues[$MinLevelFile])
    $writeToPost = ($levelValues[$Level] -ge $levelValues[$MinLevelPost])
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
        $root = Join-Path (Join-Path $base $fileLogPath) $caller

        if (-not (Test-Path $root)) { New-Item -Path $root -ItemType Directory | Out-Null }
        $date    = Get-Date -Format 'yyyy-MM-dd'
        $logPath = Join-Path $root "${date}_PID${PID}.log"
    }

    # Timestamp and render
    $timeEntry = Get-Date
    $timeStr   = $timeEntry.ToString('yyyy-MM-dd HH:mm:ss:fff')
    $plMatches = [regex]::Matches($Template, '{(?<name>\w+)}')
    $keys      = $plMatches | ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique
    $wasHash    = $Params -is [hashtable]
    $paramArray = @($Params)

    if ($ConsoleUseShortDate) {
        $timeStrConsole   = $timeEntry.ToString('HH:mm:ss')
    }
    else {
        $timeStrConsole   = $timeEntry.ToString('yyyy-MM-dd HH:mm:ss:fff')
    }

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
    $rawLine = "[$timeStr $($abbrMap[$Level])] [$caller] $msg"

    # Write to file
    if ($writeToFile) { $rawLine | Out-File -FilePath $logPath -Append -Encoding UTF8 }

    # Console output
    if ($writeConsole) {
        if ($InitialWrite) {
            # Initial invocation: write a blank line instead of overwriting
            Write-Host ""
        }
        if ($ConsoleOverwriteLastLine) {
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


        $typeColorMapping = @{
            'System.String'   = @{ Fore='Green';   Back=$null; Format={ param($v) $v } }
            'System.DateTime' = @{ Fore='Yellow';  Back=$null; Format={ param($v) $v.ToString('s') } }
            
            'System.Byte'     = @{ Fore='Cyan';    Back=$null; Format={ param($v) $v.ToString() } }
            'System.Uint32'   = @{ Fore='Cyan';    Back=$null; Format={ param($v) $v.ToString() } }
            'System.Short'   = @{ Fore='Cyan';    Back=$null; Format={ param($v) $v.ToString() } }
            'System.Int16'    = @{ Fore='Cyan';    Back=$null; Format={ param($v) $v.ToString() } }
            'System.Int32'    = @{ Fore='Cyan';    Back=$null; Format={ param($v) $v.ToString() } }
            'System.Int64'    = @{ Fore='Cyan';    Back=$null; Format={ param($v) $v.ToString() } }
            'System.Double'   = @{ Fore='Blue';    Back=$null; Format={ param($v) [math]::Round($v,2) } }
            'System.Decimal'  = @{ Fore='Blue';    Back=$null; Format={ param($v) $v.ToString() } }

            'System.Boolean'  = @{ Fore='Magenta'; Back=$null; Format={ param($v) $v.ToString() } }

            'System.Version'  = @{ Fore='Magenta'; Back=$null; Format={ param($v) $v.ToString() } }
            'Microsoft.PackageManagement.Internal.Utility.Versions.FourPartVersion' = @{ Fore='Magenta'; Back=$null; Format={ param($v) $v.ToString() } }
            'Microsoft.PowerShell.ExecutionPolicy' = @{ Fore='Magenta'; Back=$null; Format={ param($v) $v.ToString() } }
            'System.Management.Automation.ActionPreference' = @{ Fore='Green'; Back=$null; Format={ param($v) $v.ToString() } }

            # wildcard-style keys are supported (used by the lookup function via -like)
            'System.Collections.*' = @{ Fore='DarkGray'; Back=$null; Format={ param($v) ('[' + ($v.Count) + ' items]') } }
            '*[]'                  = @{ Fore='DarkGray'; Back=$null; Format={ param($v) ('[' + ($v.Length) + ' items]') } }

            # keep a Default entry for fallback
            'Default' = @{ Fore=$null; Back=$null; Format={ param($v) $v } }
        }

        function Write-Colored { param($Text,$Fore=$null,$Back=$null); if ([string]::IsNullOrEmpty($Fore) -and [string]::IsNullOrEmpty($Back)) { Write-Host -NoNewline $Text } elseif ([string]::IsNullOrEmpty($Fore)) { Write-Host -NoNewline $Text -BackgroundColor $Back } elseif ([string]::IsNullOrEmpty($Back)) { Write-Host -NoNewline $Text -ForegroundColor $Fore } else { Write-Host -NoNewline $Text -ForegroundColor $Fore -BackgroundColor $Back } ; return ("$Text").Length }

        $lineLen = 0

        # Header
        $entry = $levelMap[$Level]
        $tag   = $entry.Abbrev
        if ($entry.ContainsKey('Back')) {
            $selectedBackColor = $entry.Back
        } else {
            $selectedBackColor = $null
        }

        # Write the timestamp and tag
        $lineLen += Write-Colored "[$timeStrConsole "

        $lineLen += Write-Colored "$tag" $entry.Fore $selectedBackColor
        
        if ($SuppressConsoleCaller) {
            $lineLen += Write-Colored '] '
        }
        else {
            $lineLen += Write-Colored "] [$caller] "
        }

        # Message parts
        $pos = 0
        foreach ($m in $plMatches) {
            if ($m.Index -gt $pos) {
                $lineLen += Write-Colored $Template.Substring($pos, $m.Index - $pos)
            }
            $typeValue = $map[$m.Groups['name'].Value]
            $typeName   = $typeValue.GetType().FullName

            if ($typeColorMapping.ContainsKey($typeName)) {
                $mapped = $typeColorMapping[$typeName]
            } else {
                $mapped = $typeColorMapping['Default']
            }

            $lineLen += Write-Colored $typeValue $mapped['Fore'] $mapped['Back'] 
            $pos = $m.Index + $m.Length
        }

        if ($pos -lt $Template.Length) {
            $lineLen += Write-Colored $Template.Substring($pos)
        }

        try {
            $width = $Host.UI.RawUI.WindowSize.Width
        } catch {
            $width = 80
        }

        #$lineLen += Write-Colored (' ' * ($width-$lineLen)) $StaticForeColor $StaticBackColor

        Write-Host ''
        Write-Host -NoNewline ($esc + '[?25h')

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
        LogSpace = $LogSpace
    }

    # — new remote-post logic —
    if ($Endpoint -and $ApiKey -and $LogSpace -and $writeToPost) {
        $jsonBody = $output | ConvertTo-Json -Depth 6

        $headers = @{
            'X-API-Key'  = $ApiKey
            'X-Log-Space' = $LogSpace
        }

        # 1) Initialize failure timestamp if never set
        if (-not $script:failedAt) {
            $script:failedAt = [DateTime]::MinValue
        }

        $os = [int][System.Environment]::OSVersion.Platform
        switch ($os) {
            2 { $base = $env:LOCALAPPDATA } # Win32NT
            4 { $base = Join-Path $env:HOME ".local/share" } # Unix
            6 { $base = Join-Path $env:HOME ".local/share" } # MacOSX
            default { throw "Unsupported OS platform: $os" }
        }
        $outboxDir = Join-Path (Join-Path (Join-Path $base $fileLogPath) "Outbox") $LogSpace

        if (-not (Test-Path $outboxDir)) {
            New-Item -Path $outboxDir -ItemType Directory | Out-Null
        }

        # 2) If last failure was more than 5 minutes ago, try POST + replay queue
        if ($script:failedAt -le (Get-Date).ToUniversalTime().AddSeconds(-60)) {
            try {
                # Attempt the primary POST
                Invoke-RestMethod `
                    -Uri         $Endpoint `
                    -Method      Post `
                    -Headers     $headers `
                    -Body        $jsonBody `
                    -ContentType 'application/json' `
                    -TimeoutSec  1

                # On success, replay any queued files—but abort on first failure
                foreach ($file in Get-ChildItem -Path $outboxDir -Filter '*.json') {
                    $queuedJson = Get-Content -Path $file.FullName -Raw

                    # throttle so we don't flood the receiver
                    Start-Sleep -Milliseconds 250

                    try {
                        Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers -Body $queuedJson -ContentType 'application/json' -TimeoutSec  1

                        # Delete if successful
                        Remove-Item $file.FullName -ErrorAction SilentlyContinue
                    }
                    catch {
                        # Record the failure time, then stop processing further files
                        $script:failedAt = (Get-Date).ToUniversalTime()
                        break
                    }
                }
            }
            catch {
                # on failure of the primary send, record time and queue current payload
                $script:failedAt = (Get-Date).ToUniversalTime()
                $file = Join-Path $outboxDir ("{0:yyyyMMdd_HHmmss}_{1}.json" -f (Get-Date), $output.EventId)
                $jsonBody | Out-File -FilePath $file -Encoding UTF8
            }
        }
        else {
            # 3) If still within back-off window, just queue
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

$WriteLogInlineDefaultsProgressBar = @{
    MinLevelPost    = 'Information'
    MinLevelFile    = 'Error'
    MinLevelConsole = 'Information'
    ConsoleOverwriteLastLine = $true
    ReturnJson    = $false
    Endpoint   = 'https://localhost:8080/api/logs'
    ApiKey     = 'your_api_key_here'
    LogSpace   = 'foo'
}

$Logconfig = @{
    MinLevelPost  = 'Information'
    MinLevelFile  = 'Information'
    MinLevelConsole = 'Verbose'
    SuppressConsoleCaller = $true
    ConsoleUseShortDate = $false
    ConsoleOverwriteLastLine = $false
    ReturnJson    = $false
    Endpoint   = 'https://localhost:8080/api/logs'
    ApiKey     = 'your_api_key_here'
    LogSpace   = 'foo'
}


# Begin script
Clear-Host  


function test() {
    Out-Log @Logconfig -Level Verbose -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [int]42 }
    Out-Log @Logconfig -Level Debug -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [int64]42 }
    Out-Log @Logconfig -Level Information -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [double]42 }
    Out-Log @Logconfig -Level Warning -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [decimal]42 }
    Out-Log @Logconfig -Level Error -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [uint32]42 }
    Out-Log @Logconfig -Level Critical -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [byte]42 }
    Out-Log @Logconfig -Level Information -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = [int16]42 }

    try {
        Get-Content -Path 'C:\no-such-file.txt' -ErrorAction Stop
    }
    catch {
        Out-Log @Logconfig -Level Error -Template "Error: @Messsage: {ExceptionMessage} @Script: {ExceptionScriptName} @Line: {ExceptionLineNumber} @At: {ExceptionLine}" -Params @{ ExceptionMessage = $_.Exception.Message; ExceptionScriptName = $_.InvocationInfo.ScriptName ; ExceptionLineNumber = $_.InvocationInfo.ScriptLineNumber ; ExceptionLine = $_.InvocationInfo.Line.Trim() }
    }
    

    #Out-Log @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started."  -InitialWrite $true
}  

Start-Sleep -Milliseconds 500
Out-Log @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started.."
Start-Sleep -Milliseconds 500
Out-Log  @WriteLogInlineDefaultsProgressBar -Level Information -Template "Script execution has started..."
Start-Sleep -Milliseconds 500

Out-Log @Logconfig -Level Critical -Template "!Script execution has started." 
test
try {
    
}
catch {
    <#Do this if a terminating exception happens#>
}


#$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
#Out-Log @Logconfig -Level Critical -Template "CurrentUser policy is '{currentPolicy}'." -Params $currentPolicy 

$x=1
 




