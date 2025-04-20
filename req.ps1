function Write-Info {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    $ts = (Get-Date).ToString('HH:mm:ss')
    Write-Host "$ts  $Message" -ForegroundColor $Color
}

Write-Info 'Starting script execution ...'
#f


# Ensure the current user can run local scripts that are remotely signed
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Updated second statement—now includes the complete switch for clarity
#Write-Host "Execution policy (-ExecutionPolicy RemoteSigned) set successfully."

#Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Scope CurrentUser | Out-Null
#Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
#Install-Module PowerShellGet -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null
#Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery