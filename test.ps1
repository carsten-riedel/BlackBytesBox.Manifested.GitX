<#
.SYNOPSIS
    Writes a timestamped, leveled log message with template rendering and type-based coloring.

.DESCRIPTION
    Write-Log accepts an ILogger-style template (e.g. "{user} logged in at {time}") and a set of
    parameters (either as a positional array or named hashtable). It renders the template,
    prepends a timestamp and three-letter level tag, and writes each segment in a color
    based on the segment's .NET type. Use -UseBackColor to enable background colors for message
    values and as a fallback for level tags without a predefined Back setting.

# Default Level Color Map
# | Abbrev | Level Name  | ForegroundColor | BackgroundColor (optional) |
# |--------|-------------|-----------------|---------------------------|
# | VRB    | Verbose     | DarkGray        |                           |
# | DBG    | Debug       | Cyan            |                           |
# | INF    | Information | Green           |                           |
# | WRN    | Warning     | Yellow          |                           |
# | ERR    | Error       | Red             |                           |
# | CRT    | Critical    | White           | DarkRed                   |

.PARAMETER Level
    The log level. Valid values: Verbose, Debug, Information, Warning, Error, Critical.

.PARAMETER Template
    An ILogger-style message template containing one or more {placeholders}.

.PARAMETER Params
    Either:
      - An ordered array whose items map to template placeholders in occurrence order, or
      - A hashtable mapping placeholder names to values.

.PARAMETER UseBackColor
    Switch. If set, applies background colors for message values and as fallback for level tags
    without a Back defined in the level map.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Verbose','Debug','Information','Warning','Error','Critical')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Template,

        [Parameter(Mandatory)]
        [object]$Params,

        [switch]$UseBackColor
    )

    # Level tag definitions (Back optional)
    $levelMap = @{ 
        Verbose     = @{ Abbrev = 'VRB'; Fore = 'DarkGray' }
        Debug       = @{ Abbrev = 'DBG'; Fore = 'Cyan'     }
        Information = @{ Abbrev = 'INF'; Fore = 'Green'    }
        Warning     = @{ Abbrev = 'WRN'; Fore = 'Yellow'   }
        Error       = @{ Abbrev = 'ERR'; Fore = 'Red'      }
        Critical    = @{ Abbrev = 'CRT'; Fore = 'White'; Back = 'DarkRed' }
    }

    # Type -> Foreground color map for message values
    $typeColorMap = @{ 
        'System.String'   = 'Green'
        'System.DateTime' = 'Yellow'
        'System.Int32'    = 'Cyan'
        'System.Int64'    = 'Cyan'
        'System.Double'   = 'Blue'
        'System.Decimal'  = 'Blue'
        'System.Boolean'  = 'Magenta'
        'Default'         = 'White'
    }

    # Static defaults
    $staticFore = 'White'
    $staticBack = 'Black'

    # Helper: write with optional BackColor
    function Write-Colored {
        param(
            [string]$Text,
            [string]$ForeColor,
            [string]$BackColor
        )
        if ($UseBackColor -and $BackColor) {
            Write-Host -NoNewline $Text -ForegroundColor $ForeColor -BackgroundColor $BackColor
        } else {
            Write-Host -NoNewline $Text -ForegroundColor $ForeColor
        }
    }

    # Build timestamp and level tag
    $timeEntry = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss:fff')
    $entry     = $levelMap[$Level]
    $tag       = $entry.Abbrev

    # Determine level tag BackColor logic
    if ($entry.ContainsKey('Back')) {
        $lvlBack = $entry.Back
    } elseif ($UseBackColor) {
        $lvlBack = $staticBack
    } else {
        $lvlBack = $null
    }

    # Extract placeholders
    $plMatches = [regex]::Matches($Template, '{(?<name>\w+)}')
    $keys      = $plMatches | ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique

    # Bind Params to placeholder names
    if ($Params -is [hashtable]) {
        $map = $Params
    } else {
        $map = @{ }
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $map[$keys[$i]] = $Params[$i]
        }
    }

    # Split template into colored segments
    $segments = @()
    $pos = 0
    foreach ($m in $plMatches) {
        # static text
        if ($m.Index -gt $pos) {
            $text = $Template.Substring($pos, $m.Index - $pos)
            $segments += [PSCustomObject]@{ Text = $text; Fore = $staticFore; Back = $staticBack }
        }
        # placeholder value
        $name = $m.Groups['name'].Value
        $value = $map[$name]
        $typeName = $value.GetType().FullName
        if ($typeColorMap.ContainsKey($typeName)) {
            $fore = $typeColorMap[$typeName]
        } else {
            $fore = $typeColorMap['Default']
        }
        # message value BackColor
        if ($UseBackColor) {
            $back = $staticBack
        } else {
            $back = $null
        }
        $segments += [PSCustomObject]@{ Text = $value; Fore = $fore; Back = $back }
        $pos = $m.Index + $m.Length
    }
    # Trailing static text
    if ($pos -lt $Template.Length) {
        $text = $Template.Substring($pos)
        if ($UseBackColor) {
            $back = $staticBack
        } else {
            $back = $null
        }
        $segments += [PSCustomObject]@{ Text = $text; Fore = $staticFore; Back = $back }
    }

    # Output header: [timestamp ]
    Write-Colored '['        $staticFore  $staticBack
    Write-Colored $timeEntry $staticFore  $staticBack
    Write-Colored ' '        $staticFore  $staticBack

    # Output level tag with Back logic ignoring switch for predefined Back
    if ($lvlBack) {
        Write-Host -NoNewline $tag -ForegroundColor $entry.Fore -BackgroundColor $lvlBack
    } else {
        Write-Host -NoNewline $tag -ForegroundColor $entry.Fore
    }

    Write-Colored '] '       $staticFore  $staticBack

    # Output message segments
    foreach ($seg in $segments) {
        Write-Colored $seg.Text $seg.Fore $seg.Back
    }
    Write-Host ''
}



Write-Log -Level Verbose -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1, 1.2 -UseBackColor
Write-Log -Level Verbose -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date)
Write-Log -Level Debug -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date)
Write-Log -Level Information -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date)
Write-Log -Level Warning -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date)
Write-Log -Level Error -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date)
Write-Log -Level Critical -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date) -UseBackColor
Write-Log -Level Critical -Template "{hello}-{world} number {num} at {time} !" -Params "Hello","World",1,(Get-Date) 