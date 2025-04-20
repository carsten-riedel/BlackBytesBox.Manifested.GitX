# Full execution switch: -ExecutionPolicy RemoteSigned

Write-Host "Starting script execution ..."

# Ensure the current user can run local scripts that are remotely signed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -Verbose

# Updated second statement—now includes the complete switch for clarity
Write-Host "Execution policy (-ExecutionPolicy RemoteSigned) set successfully."