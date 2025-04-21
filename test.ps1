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
    $timeEntry = Get-Date
    $timeStr   = $timeEntry.ToString('yyyy-MM-dd HH:mm:ss:fff')
    $plMatches = [regex]::Matches($Template, '{(?<name>\w+)}')
    $keys      = $plMatches | ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique
    if ($Params -is [hashtable]) {
        $map = $Params
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
    Downloads content from a URI to a file with inline progress logging.

.DESCRIPTION
    Sends an HTTP request and streams the response content in chunks to a local file.
    Reports progress via Write-LogInline, supports overwrite control, custom headers,
    timeouts, credentials, and configurable buffer size.

.PARAMETER Uri
    The URI to download. Must be a non-empty string.

.PARAMETER OutFile
    Path to save the downloaded file. Must be a non-empty string. Use -Force to overwrite.

.PARAMETER Method
    HTTP method to use. Default: GET.

.PARAMETER Headers
    Hashtable of HTTP headers to include in the request.

.PARAMETER TimeoutSec
    Timeout in seconds for the request (0 = infinite). Default: 0.

.PARAMETER Credential
    PSCredential for authenticated requests.

.PARAMETER Body
    Byte[] payload for POST/PUT/PATCH methods. Implicit ParameterSet triggers with-body logic.

.PARAMETER Force
    Switch to overwrite existing OutFile.

.PARAMETER BufferSize
    Size in bytes of each read buffer. Default: 4MB.

.EXAMPLE
    Invoke-WebRequestEx -Uri 'https://example.com/large.bin' \
                        -OutFile 'C:\temp\large.bin' \
                        -Force
#>
function Invoke-WebRequestEx {
    [CmdletBinding(DefaultParameterSetName = 'NoBody')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $OutFile,

        [Parameter()]
        [ValidateSet('GET','POST','PUT','DELETE','HEAD','OPTIONS','PATCH')]
        [string] $Method = 'GET',

        [Parameter()]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $TimeoutSec = 0,

        [Parameter()]
        [System.Management.Automation.PSCredential] $Credential,

        [Parameter(ParameterSetName = 'WithBody')]
        [byte[]] $Body,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [ValidateRange(1, [long]::MaxValue)]
        [long] $BufferSize = 4MB
    )

    # Prepare output file
    if (Test-Path $OutFile) {
        if (-not $Force) {
            throw "File '$OutFile' already exists. Use -Force to overwrite."
        }
    }

    Write-LogInline -Level Information `
                    -Template "Preparing download: {uri} to {file}" `
                    -Params @{ uri = $Uri; file = $OutFile } `
                    -Overwrite

    # Initialize WebRequest
    $req = [System.Net.WebRequest]::Create($Uri)
    $req.Method = $Method
    if ($TimeoutSec -gt 0) {
        $req.Timeout = $TimeoutSec * 1000
        $req.ReadWriteTimeout = $TimeoutSec * 1000
    }
    if ($Credential) { $req.Credentials = $Credential }
    if ($Headers) { $Headers.GetEnumerator() | ForEach-Object { $req.Headers.Add($_.Name, $_.Value) } }

    if ($PSCmdlet.ParameterSetName -eq 'WithBody') {
        if ($Method -notin 'POST','PUT','PATCH') {
            throw "Body parameter is only allowed with POST, PUT, or PATCH methods."
        }
        $req.ContentLength = $Body.Length
        $stream = $req.GetRequestStream()
        $stream.Write($Body, 0, $Body.Length)
        $stream.Close()
    }

    try {
        $resp = $req.GetResponse()
        $inStream = $resp.GetResponseStream()
        $mode = if ($Force) { 'Create' } else { 'CreateNew' }
        $outStream = [System.IO.File]::Open($OutFile, $mode)

        $total      = $resp.ContentLength
        $downloaded = 0
        $buffer     = New-Object byte[] $BufferSize

        while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
            $downloaded += $read

            if ($total -gt 0) {
                $pct = [math]::Round(100 * $downloaded / $total, 1)
                Write-LogInline -Level Information `
                                -Template "Downloaded {pct}% ({done}/{total} bytes)" `
                                -Params @{ pct = $pct; done = $downloaded; total = $total } `
                                -Overwrite
            }
            else {
                Write-LogInline -Level Information `
                                -Template "Downloaded {bytes} bytes..." `
                                -Params @{ bytes = $downloaded } `
                                -Overwrite
            }
        }

        Write-LogInline -Level Information `
                        -Template "Download complete: {file}" `
                        -Params @{ file = $OutFile } `
                        -Overwrite:$false
    }
    catch {
        Write-LogInline -Level Error `
                        -Template "Download failed: {err}" `
                        -Params @{ err = $_.Exception.Message } `
                        -Overwrite:$false
        throw $_
    }
    finally {
        $inStream?.Dispose()
        $outStream?.Dispose()
    }
}


$WriteLogInlineDefaults = @{
    FileMinLevel  = 'Verbose'
    MinLevel     = 'Verbose'
    UseBackColor = $false
    Overwrite    = $true
    FileAppName  = "testing"
    ReturnJson = $false
 }


Write-LogInline -Level Verbose -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1, 1.2 @WriteLogInlineDefaults -InitialWrite
Start-Sleep -Seconds 2
Write-LogInline -Level Debug -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World1",1, 1.33333 @WriteLogInlineDefaults
Start-Sleep -Seconds 2
Write-LogInline -Level Information -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1, 1.4 @WriteLogInlineDefaults
Start-Sleep -Seconds 2
Write-LogInline -Level Error -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World2",1, 1.5 @WriteLogInlineDefaults
Start-Sleep -Seconds 2
Write-LogInline -Level Critical -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1, 1.6 @WriteLogInlineDefaults
Start-Sleep -Seconds 2

Invoke-WebRequestEx -Uri 'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct/raw/main/model.safetensors' -OutFile 'C:\temp\x.bin' -Force

