function load-Config {
    param([string]$Path)
    if (Test-Path $Path) {
        return Get-Content $Path | ConvertFrom-Json
    } else {
        return @{}
    }
}

function Save-Config {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [string]$Path
    )
    $Config | ConvertTo-Json -Depth 5 | Out-File $Path
}

function Prompt-MissingValues {
    param([hashtable]$Config)

    $fields = @{
        RESOURCE_GROUP = "Enter Resource Group"
        FRONT_DOOR_PROFILE = "Enter Front Door Profile"
        FRONTDOOR_SKU = "Enter Front Door SKU (Default: Standard_AzureFrontDoor)"
        FUNCTION_APP_NAME = "Enter Function App Name"
        BACKEND_FQDN = "Enter Backend FQDN"
        LOCATION = "Enter Location (Default: eastus)"
        STORAGE_ACCOUNT = "Enter Storage Account Name"
        STORAGE_SKU = "Enter Storage SKU (Default: Standard_LRS)"
        PX_APPID = "Enter HUMAN App ID (provided by HUMAN)"
        PX_AUTH_TOKEN = "Enter HUMAN Auth Token (provided by HUMAN)"
        PX_COOKIE_SECRET = "Enter HUMAN Cookie Secret (provided by HUMAN)"
        RULESET_NAME = "Enter Ruleset Name (default: HumanRuleSet)"
        ENDPOINT = "Enter Endpoint Subdomain"
    }

    foreach ($key in $fields.Keys) {
        if (-not $Config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($Config[$key])) {
            $default = $fields[$key] -match 'default: (.+)' ? $matches[1] : ''
            $prompt = "$($fields[$key])"
            $input = Read-Host "$prompt"
            if ([string]:IsNullOrWhiteSpace($input) -and $default) {
                $input = $default
            }
            $Config[$key] = $input
        }
    }

    return $Config
}

function Deploy-StorageAccount {
    param([hashtable]$Config)
    Write-Host "Creating Storage Account..." -ForegroundColor Cyan
    az storage account create --name $Config.STORAGE_ACCOUNT `
        --resource-group $Config.RESOURCE_GROUP `
        --location $Config.LOCATION `
        --sku $Config.STORAGE_SKU | Out-Null
}

function Deploy-FunctionApp {
    param([hashtable]$Config)
    Write-Host "Creating Function App..." -ForegroundColor Cyan
    az functionapp create `
        --name $Config.FUNCTION_APP_NAME `
        --storage-account $Config.STORAGE_ACCOUNT `
        --resource-group $Config.RESOURCE_GROUP `
        --consumption-plan-location $Config.LOCATION `
        --runtime node `
        --runtime-version 22 `
        --os-type Linux | Out-Null
}

function Set-FunctionAppSettings {
    param([hashtable]$Config)
    Write-Host "Setting app settings..." -ForegroundColor Cyan
    $settings = @{
        PX_COOKIE_SECRET        = $Config.PX_COOKIE_SECRET
        PX_APP_ID               = $Config.PX_APP_ID
        PX_AUTH_TOKEN           = $Config.PX_AUTH_TOKEN
        FRONT_DOOR_SECRET_KEY   = ([guid]::NewGuid().ToString("N"))
        PX_MODULE_MODE          = "monitor"
    }
    foreach ($key in $settings.Keys) {
        az functionapp config appsettings set `
            --name $Config.FUNCTION_APP_NAME `
            --resource-group $Config.RESOURCE_GROUP `
            --settings "$key=$($settings[$key])" | Out-Null
    }
}

function Clone-And-Build-Project {
    Write-Host "Cloning and building project..." --ForegroundColor Cyan
    if (-not (Test-Path "azure-enforcer-template")) {
        git clone https://github.com/PerimeterX/azure-enforcer-template.git
    }
    Push-Location azure-enforcer-template
    npm install
    npm run build
    Pop-Location
}

function Publish-FunctionApp {
    param([hashtable]$Config)
    Push-Location azure-enforcer-template
    Write-Host "Publishing Function App..." -ForegroundColor Cyan
    func azure functionapp publish $Config.FUNCTION_APP_NAME --typescript
    Pop-Location
}