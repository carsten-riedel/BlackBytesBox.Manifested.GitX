Write-Output "Hello, World!"
Write-Output "This is a PowerShell script."


powershell -NoProfile -ExecutionPolicy Unrestricted -Command "& {
    Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Scope CurrentUser | Out-Null;
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
    Install-Module PowerShellGet -Force -Scope CurrentUser -AllowClobber -WarningAction SilentlyContinue | Out-Null;
    Install-Module -Name BlackBytesBox.Manifested.Initialize -Scope CurrentUser -AllowClobber -Force -Repository PSGallery;
}" ; exit