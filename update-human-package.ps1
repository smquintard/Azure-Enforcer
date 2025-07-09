#update-human-and-deploy.ps1

#Force Azure Login
Write-Host "logging into Azure..."
az login --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Azure login failed. Exiting."
    exit 1
}

#Variables
$functionAppName = "" #functionApp Name
$resourceGroup = "" #resourceGroup Name
$repoUrl = "https://github.com/PerimeterX/azure-enforcer-template.git"
$localPath = "" #local storage path where repo pull should put the updated version

#Clone or pull latest repo
if (-Not (Test-Path $localPath)) {
    git clone $repoUrl $localPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone repo. Exiting"
        exit 1
    }
} else {
    Write-Host "Repo already exists. Pulling latest changes..."
    Set-Location $localPath
    git pull
    Set-Location ..
}

#Go to project directory
Set-Location $localPath

#Install Dependencies
Write-Host "Installing npm packages..."
npm install

#Update HUMAN
Write-Host "Updating @HUMAN Azure FrontDoor to latest version..."
npm install @PerimeterX/human@latest

#Build the function
Write-Host "Running build..."
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed. Exiting."
    exit 1
}

#Publish to Azure
Write-Host "Publishing to Azure Function App: $functionAppName"
func azure functionapp publish $functionAppName --typescript
if ($LASTEXITCODE -ne 0) {
    Write-Error "Function App Deployment Failed"
    exit 1
}

Write-Host "Function App has been updated and redeployed successfully."