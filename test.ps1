
. "$PSScriptRoot\Out-Log.ps1"

$Logconfig = @{
    MinLevelPost  = 'Information'
    MinLevelFile  = 'Information'
    MinLevelConsole = 'Verbose'
    SuppressConsoleCaller = $true
    UseShortConsoleDate = $true
    UseBackColor  = $false
    Overwrite     = $false
    ReturnJson    = $false
    Endpoint   = 'https://localhost:8080/api/logs'
    ApiKey     = 'your_api_key_here'
    LogSpace   = 'foo'
}

Out-Log @Logconfig -Level Verbose -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = 42 }
Out-Log @Logconfig -Level Debug -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = 42 }
Out-Log @Logconfig -Level Information -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = 42 }
Out-Log @Logconfig -Level Warning -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = 42 }
Out-Log @Logconfig -Level Error -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = 42 }
Out-Log @Logconfig -Level Critical -Template "{Name} {Value} called." -Params @{ Name = 'TestFunction'; Value = 42 }


