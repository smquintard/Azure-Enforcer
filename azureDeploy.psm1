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

function Publish-FunctionApp {
    param([hashtable]$Config)
    Push-Location azure-enforcer-template
    Write-Host "Publishing Function App..." -ForegroundColor Cyan
    func azure functionapp publish $Config.FUNCTION_APP_NAME --typescript
    Pop-Location
}

function Configure-FrontDoorRuleset {
    param([hashtable]$Config)

    Write-Host "Creating Front Door Ruleset..." -ForegroundColor Cyan
    az afd rule-set create
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE | Out-Null
        
    #Rule 1 - Header Injection
    Write-Host "Creating Rule 1 - Header Injection..." -ForegroundColor Cyan
    az afd rule create
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE
        --order 1
        --match-variable UrlPath
        --operator BeginsWith
        --match-values "/$($Config.PX_APPID.Substring(0,6))/"
        --rule-name HSFirstPartyHeaders
        --action-name ModifyRequestHeader
        --header-action Append
        --header-name "x-px-first-party"
        --header-value "1"
        --match-processing-behavior Continue | Out-Null

    az afd rule action function
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE
        --rule-name HSFirstPartyHeaders
        --action-name ModifyRequestHeader
        --header-action Append
        --header-name "x-px-enforcer-true-ip"
        --header-value "{client_ip}" | Out-Null

    #Rule 2 - JS Rewrite
    Write-Host "Creating Rule 2 - JS Rewrite..." -ForegroundColor Cyan
    az afd rule create
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE
        --order 2
        --match-variable UrlPath
        --operator Equal
        --match-values "/$($Config.PX_APPID.Substring(0,6))/init.js"
        --rule-name HSFirstPartyClient
        --action-name UrlRewrite
        --source-pattern "/$($Config.PX_APPID.Substring(0,6))/init.js"
        --destination "/$($Config.PX_APP_ID)/main.min.js"
        --preserve-unmatched-path No
        --match-processing-behavior Stop | Out-Null

    az afd rule action add
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE
        --rule-name HSFirstPartyClient
        --action-name RouteConfigurationOverride
        --origin-group HSClient
        --forwarding-protocol MatchRequest
        --enable-caching false | Out-Null

    #Rule 3 Captcha Rewrite
    Write-Host "Creating Rule 3 - Captcha Rewrite..." -ForegroundColor Cyan
    az afd rule create
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE
        --order 3
        --match-variable UrlPath
        --operator BeginsWith
        --match-values "/$($Config.PX_APPID.Substring(0,6))/captcha"
        --rule-name HSFirstPartyCaptcha
        --action-name UrlRewrite
        --source-pattern "/$($Config.PX_APPID.Substring(0,6))/captcha"
        --destination "/$($Config.PX_APPID)"
        --preserve-unmatched-path Yes
        --match-processing-behavior Stop | Out-Null

    az afd rule action add
        --resource-group $Config.RESOURCE_GROUP
        --rule-set-name $Config.RULESET_NAME
        --profile-name $Config.FRONT_DOOR_PROFILE
        --rule-name HSFirstPartyCaptcha
        --action-name RouteConfigurationOverride
        --origin-group HSCaptcha
        --forwarding-protocol MatchRequest
        --enable-caching false | Out-Null

    # Rule 4 - XHR Rewrite
    Write-Host "Creating Rule 4 (XHR Rewrite)..." -ForegroundColor Cyan
    az afd rule create `
        --resource-group $Config.RESOURCE_GROUP `
        --rule-set-name $Config.RULESET_NAME `
        --profile-name $Config.FRONT_DOOR_PROFILE `
        --order 4 `
        --match-variable UrlPath `
        --operator BeginsWith `
        --match-values "/$($Config.PX_APPID.Substring(0,6))/xhr" `
        --rule-name HSFirstPartyXHR `
        --action-name UrlRewrite `
        --source-pattern "/$($Config.PX_APPID.Substring(0,6))/xhr" `
        --destination "/" `
        --preserve-unmatched-path Yes `
        --match-processing-behavior Stop | Out-Null

    az afd rule action add `
        --resource-group $Config.RESOURCE_GROUP `
        --rule-set-name $Config.RULESET_NAME `
        --profile-name $Config.FRONT_DOOR_PROFILE `
        --rule-name HSFirstPartyXHR `
        --action-name RouteConfigurationOverride `
        --origin-group HSCollector `
        --forwarding-protocol MatchRequest `
        --enable-caching false | Out-Null

    # Rule 5 - Header overwrite if not authenticated
    Write-Host "Creating Rule 5 (Header Overwrite)..." -ForegroundColor Cyan
    az afd rule create `
        --resource-group $Config.RESOURCE_GROUP `
        --rule-set-name $Config.RULESET_NAME `
        --profile-name $Config.FRONT_DOOR_PROFILE `
        --order 6 `
        --match-variable RequestHeader `
        --selector "x-enforcer-auth" `
        --operator Equal `
        --negate-condition true `
        --match-values $Config.SECRET_KEY `
        --transforms Trim `
        --rule-name HSUnenforcedRequest `
        --action-name ModifyRequestHeader `
        --header-action Overwrite `
        --header-name "x-functions-key" `
        --header-value "<enter unique value before deployment>" `
        --match-processing-behavior Stop | Out-Null

    az afd rule action add `
        --resource-group $Config.RESOURCE_GROUP `
        --rule-set-name $Config.RULESET_NAME `
        --profile-name $Config.FRONT_DOOR_PROFILE `
        --rule-name HSUnenforcedRequest `
        --action-name RouteConfigurationOverride `
        --origin-group HSEnforcer `
        --forwarding-protocol MatchRequest `
        --enable-caching false | Out-Null

    # Create the route
    Write-Host "Creating Front Door Route..." -ForegroundColor Cyan
    az afd route create `
        -g $Config.RESOURCE_GROUP `
        --endpoint-name $Config.ENDPOINT `
        --profile-name $Config.FRONT_DOOR_PROFILE `
        --route-name HumanSecurityRoute `
        --rule-sets $Config.RULESET_NAME `
        --origin-group BackendOrigin `
        --supported-protocols Http Https `
        --link-to-default-domain Enabled `
        --forwarding-protocol MatchRequest `
        --https-redirect Disabled | Out-Null

    Write-Host "✅ Route and Ruleset configuration complete." -ForegroundColor Green

}
