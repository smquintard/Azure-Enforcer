# deploy.ps1

# Require login at the beginning
az login | Out-Null

# Run npm update check early
Write-Host "`n🔍 Checking for npm updates..." -ForegroundColor Cyan
try {
    npm update -g
    Write-Host "✅ npm packages updated successfully." -ForegroundColor Green
} catch {
    Write-Warning "⚠️ npm update failed. You may want to update manually."
}

# Define and load config
$configPath = "$PSScriptRoot\config.json"

if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
} else {
    $config = [PSCustomObject]@{}
}

# Load module
Import-Module "$PSScriptRoot\modules\azureDeploy.psm1" -Force

# Prompt for missing values
$config = Prompt-MissingValues -config $config

# Save config
Save-Config -config $config -path $configPath

# Begin deployment steps
Deploy-StorageAccount -config $config
Deploy-FunctionApp -config $config
Set-FunctionAppSettings -config $config
Clone-And-Build-Project
Publish-FunctionApp -config $config

Write-Host "`n🎉 Deployment complete!" -ForegroundColor Green
