# deploy.ps1

# Require login at the beginning
Write-Host "`n🔐 Logging into Azure..." -ForegroundColor Cyan
az login | Out-Null

# Run npm update check early
Write-Host "`n🔍 Checking for global npm updates..." -ForegroundColor Cyan
try {
    npm update -g
    Write-Host "✅ npm packages updated successfully." -ForegroundColor Green
} catch {
    Write-Warning "⚠️ npm update failed. You may want to update manually."
}

# Define and load config
$configPath = "$PSScriptRoot\config.json"

if (Test-Path $configPath) {
    $Config = Get-Content $configPath | ConvertFrom-Json
} else {
    $Config = [PSCustomObject]@{}
}

# Load deployment module
$modulePath = "$PSScriptRoot\modules\azureDeploy.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Error "❌ Module not found at path: $modulePath"
    exit 1
}

# Prompt for missing values
$Config = Prompt-MissingValues -Config (load-Config -Path $configPath)

#Run Deployment Steps
Deploy-StorageAccount -Config $Config
Deploy-FunctionApp -Config $Config
Set-FunctionAppSettings -Config $Config
Publish-FunctionApp -Config $Config
Configure-FrontDoorRuleset -Config $Config

# Save config
Save-Config -Config $Config -Path ".\config.json"

Write-Host "`n🎉 Deployment complete!" -ForegroundColor Green
