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
    Write-Info -Message 'Configuring execution policy to allow running PowerShell modules and scripts...' -Color Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Write-Info -Message 'Execution policy set to RemoteSigned. PowerShell modules and scripts can now run.' -Color Green
}
catch {
    Write-Info -Message "ERROR: Failed to configure execution policy (RemoteSigned). $_" -Color Red
    exit 1
}


try {
    Write-Info -Message 'Installing NuGet Package Provider...' -Color Yellow
    Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Scope CurrentUser | Out-Null
    Write-Info -Message 'NuGet Package Provider installed successfully.' -Color Green
}
catch {
    Write-Info -Message "ERROR: Failed to install NuGet Package Provider. $_" -Color Red
    exit 1
}

try {
    Write-Info -Message 'Setting PSGallery as a trusted repository...' -Color Yellow
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-Info -Message 'PSGallery is now trusted.' -Color Green
}
catch {
    Write-Info -Message "ERROR: Failed to trust PSGallery. $_" -Color Red
    exit 1
}

try {
    Write-Info -Message 'Updating PowerShellGet module...' -Color Yellow
    Install-Module -Name PowerShellGet -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
    Write-Info -Message 'PowerShellGet module updated successfully.' -Color Green
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



# Ensure the current user can run local scripts that are remotely signed
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Updated second statement—now includes the complete switch for clarity
#Write-Host "Execution policy (-ExecutionPolicy RemoteSigned) set successfully."

#Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Scope CurrentUser | Out-Null
#Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
#Install-Module PowerShellGet -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
#Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery