PowerShell Azure Automation Script - Usage Guide

1. Prerequisties
Before using this script, make sure the following tools are installed:
- PowerShell 5.1+ or PowerShell Core (7.x)
- Azure CLI (download from hxxps://learn.microsoft.com)
- Node.js and npm (download from hxxps://nodejs.org)
- Azure Functions Core Tools (func) - install using following command: npm install -g azure-functions-core-tools@4 --unsafe-perm true
- Git (Clone project) (download Git from hxxps://git-scm.com/downlaods)

2. Folder Structure
Make sure to organize the folder structure in the following manner:

project-root/
│
├── deploy.ps1
├── config.json
└── modules/
    └── azureDeploy.psm1

 - deploy.ps1 (main script that is executed)
 - config.json (configuration file)
 - modules/azureDeploy.psm1 - Reusable module with deployment logic

If you are going to change the project root directory, then make sure to update this documentation to ensure that a clear record is kept where the project root lives


3. How to Run the Script
 - Open PowerShell and navigate to the project root directory

 cd path\to\project-root

 - Execute the Script

 ./deploy.ps1

What will happen:
 - Prompted to log in to Azure
 - Script checks config.json for existing values
 - Any missing values are prompted via the terminal
 - Config is saved/updated in config.json
 - The script:
    - Creates the storage account
    - Deploys the Function App
    - Sets the App Settings
    - Clones and builds the Github Repo (this can be skipped)
    - Publishes the Function App
    - Checks for npm package updates

4. Configuration: (config.json)
- This file holds all deployment variables. It can be left blank or it can be filled in prior to deployment.

5. How This All Works
 - The script imports the PowerShell module using:

 Import-Module "$PSScriptRoot\modules\azureDeploy.psm1" -Force

 - The Prompt-MissingValues function checks for missing fields and prompts the user
 - The Save-Config function saves updated values back to config.json
 - Deployment stesp are organized into separate functions:
    - Deploy-StorageAccount
    - Deploy-FunctionApp
    - Set-FunctionAppSettings
    - Publish-FunctionApp

6. Customize Paths or logic
 - If the repo URL changes, update this line in Clone-And-Build-project
    - git clone https://github.com/PerimeterX/azure-enforcer-template.git

 - If you want to change the runtime version, update:
    --runtime-version 18

 - If the config file is located elsewhere, change this line in deploy.ps1
  $configPath = "$PSScriptRoot\config.json"


7. Notes and Troubleshooting

- az not recognized:            Ensure Azure CLI is in your system path
- func not found:               Install Azure Functions Core Tools
- Errors with Config            Delete config.json to regenerate via prompts
- Permission Issues             Run PowerShell as Administrator, make sure appropriate rights exist in Azure
- Proxy issues with npm/git     Configure npm and git to use your network proxy, make sure you are logged into Git to push project to git
