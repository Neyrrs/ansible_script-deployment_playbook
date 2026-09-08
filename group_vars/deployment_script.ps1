<powershell>
# Require PowerShell 5.0 or later

# Set log path
$env:LogPath = "$env:appdata\Trend Micro\V1ES"
New-Item -path $env:LogPath -type directory -Force
Start-Transcript -path "$env:LogPath\v1es_install.log" -append
## Pre-Check
# Check authorization
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "$(Get-Date -format T) You are not running as an Administrator. Please try again with admin privileges." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Check if Invoke-WebRequest is available
if (-not (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) {
    Write-Host "$(Get-Date -format T) Invoke-WebRequest is not available. Please install PowerShell 3.0 or later." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Check if Expand-Archive is available
if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
    Write-Host "$(Get-Date -format T) Expand-Archive is not available. Please install PowerShell 5.0 or later." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "$(Get-Date -format T) Start deploying." -ForegroundColor White

# Proxy_Addr_Port and Proxy_User/Proxy_Password define proxy for software download and agent activation
$PROXY_ADDR_PORT="" 
$PROXY_USERNAME=""
$PROXY_PASSWORD=""

# Compose proxy URI, credential, and credential object
$PROXY_URI=""
$PROXY_CREDENTIAL=""
$PROXY_CREDENTIAL_OBJ=$null
if ($PROXY_ADDR_PORT.Length -ne 0) {
    $PROXY_ADDR_PORT=$PROXY_ADDR_PORT.Trim()
    $PROXY_URI="http://$PROXY_ADDR_PORT"

    if ($PROXY_USERNAME.Length -ne 0) {
        $PROXY_USERNAME=$PROXY_USERNAME.Trim()
        $PROXY_CREDENTIAL="${PROXY_USERNAME}:"
        $PROXY_CREDENTIAL_OBJ = New-Object System.Management.Automation.PSCredential ($PROXY_USERNAME, (new-object System.Security.SecureString))

        if ($PROXY_PASSWORD.Length -ne 0) {
            $PROXY_PASSWORD=$PROXY_PASSWORD.Trim()
            $PROXY_CREDENTIAL="${PROXY_USERNAME}:${PROXY_PASSWORD}"
            $PROXY_CREDENTIAL_OBJ = New-Object System.Management.Automation.PSCredential ($PROXY_USERNAME, (ConvertTo-SecureString -String $PROXY_PASSWORD -AsPlainText -Force))
        }

        # Encode proxy credential by base64
        $CREDENTIAL_ENCODE=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PROXY_CREDENTIAL))
        $PROXY_URI="$CREDENTIAL_ENCODE@$PROXY_ADDR_PORT" # Don't prepend "http://" to the proxy URI
    }
}
## Get Package
$XBC_INSTALLER_PATH = "$env:TEMP\XBC_Installer.zip"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## Download XBC installer
$XBC_FQDN="api-us1.xbc.trendmicro.com"
$GET_INSTALLER_URL="https://$XBC_FQDN/apk/installer"
$HTTP_BODY='{"company_id":"fc70b102-4ac9-42f9-ad96-a3b20b01f0a9","platform":"win32","scenario_ids":["a6f84c9a-5526-4bf8-9ce9-6da72be6aabe","b164b828-2bf0-4289-a5cd-afb4cf6de03c"]}'
$HTTP_HEADER = @{"X-Customer-Id"="fc70b102-4ac9-42f9-ad96-a3b20b01f0a9"}

Write-Host "$(Get-Date -format T) Start downloading the installer." -ForegroundColor White

$oldProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    if ($PROXY_ADDR_PORT.Length -eq 0) {
        $response = Invoke-WebRequest -Uri "$GET_INSTALLER_URL" -Method Post -Body "$HTTP_BODY" -ContentType "application/json" -Headers $HTTP_HEADER -OutFile "$XBC_INSTALLER_PATH" -UseBasicParsing
    }
    elseif ($PROXY_CREDENTIAL.Length -eq 0) {
        $response = Invoke-WebRequest -Uri "$GET_INSTALLER_URL" -Method Post -Body "$HTTP_BODY" -ContentType "application/json" -Proxy "http://$PROXY_ADDR_PORT" -Headers $HTTP_HEADER -OutFile "$XBC_INSTALLER_PATH" -UseBasicParsing
    }
    else {
        $response = Invoke-WebRequest -Uri "$GET_INSTALLER_URL" -Method Post -Body "$HTTP_BODY" -ContentType "application/json" -Proxy "http://$PROXY_ADDR_PORT" -ProxyCredential $PROXY_CREDENTIAL_OBJ -Headers $HTTP_HEADER -OutFile "$XBC_INSTALLER_PATH" -UseBasicParsing
    }
    if ($response.StatusCode -ge 400) {
        Write-Host "$(Get-Date -format T) Failed to download the installer." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Host "$(Get-Date -format T) Failed to download the installer." -ForegroundColor Red
    Stop-Transcript
    exit 1
} finally {
    $ProgressPreference = $oldProgressPreference
}
Write-Host "$(Get-Date -format T) The installer was downloaded to $XBC_INSTALLER_PATH." -ForegroundColor White
## Unzip XBC installer / full package
$XBC_INSTALLER_DIR = "$env:TEMP\XBC_Installer"
Write-Host "$(Get-Date -format T) Start unzipping the installer / full package." -ForegroundColor White
try {
    Expand-Archive -Path $XBC_INSTALLER_PATH -DestinationPath $XBC_INSTALLER_DIR -Force
    Write-Host "$(Get-Date -format T) The installer / full package was unzipped to $XBC_INSTALLER_DIR." -ForegroundColor White
} catch {
    Write-Host "$(Get-Date -format T) Failed to unzip the installer / full package. Error: $_.Exception.Message." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

## Install XBC
$XBC_INSTALLER_EXE = "$XBC_INSTALLER_DIR\EndpointBasecamp.exe"

$ARCH_TYPE = if ([System.Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }

# Architecture = x86 (0), x64 (9), ARM64 (12)
$IS_AARCH64 = (Get-WmiObject -Class Win32_Processor | Select-Object -ExpandProperty Architecture) -eq 12
$AGENT_TOKEN_WIN64 = "a6f84c9a-5526-4bf8-9ce9-6da72be6aabe;b164b828-2bf0-4289-a5cd-afb4cf6de03c"
$AGENT_TOKEN_WIN32 = "a6f84c9a-5526-4bf8-9ce9-6da72be6aabe;b164b828-2bf0-4289-a5cd-afb4cf6de03c"
$AGENT_TOKEN_AARCH64 = "a6f84c9a-5526-4bf8-9ce9-6da72be6aabe;b164b828-2bf0-4289-a5cd-afb4cf6de03c"
$FQDN_ARG=@()
$GROUP_ID_ARG=@()
Write-Host "$(Get-Date -format T) Start installing the agent." -ForegroundColor White
try {
    if ($PROXY_ADDR_PORT.Length -eq 0) {
        $CONNECT_CONFIG = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"fps":[{"connections": [{"type": "DIRECT_CONNECT"}]}]}'))
    } else {
        $CONNECT_CONFIG = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"fps":[{"connections": [{"type": "USER_INPUT"}]}]}'))
    }

	if ($IS_AARCH64) {
		$XBC_AGENT_TOKEN = $AGENT_TOKEN_AARCH64
	}
	elseif ($ARCH_TYPE -eq "x86_64"){
		 $XBC_AGENT_TOKEN = $AGENT_TOKEN_WIN64
	}
	else {
        $XBC_AGENT_TOKEN = $AGENT_TOKEN_WIN32
    }
	
    if ($PROXY_URI.Length -ne 0) {
		$result = & "$XBC_INSTALLER_EXE" /connection $CONNECT_CONFIG /agent_token $XBC_AGENT_TOKEN /is_full_package true /proxy_server_port $PROXY_URI @FQDN_ARG @GROUP_ID_ARG
	} else {
		$result = & "$XBC_INSTALLER_EXE" /connection $CONNECT_CONFIG /agent_token $XBC_AGENT_TOKEN /is_full_package true @FQDN_ARG @GROUP_ID_ARG
	}
    $exitCode = $LASTEXITCODE
	if ($exitCode -ne 0) {
		Write-Host "$(Get-Date -format T) Failed to install the agent. Error: $result" -ForegroundColor Red
		Stop-Transcript
		exit 1
	}
    Write-Host "$(Get-Date -format T) The agent is installed." -ForegroundColor White
} catch {
    Write-Host "$(Get-Date -format T) Failed to install the agent." -ForegroundColor Red
    Stop-Transcript
    exit 1
}
## Check XBC registration
if ($ARCH_TYPE -eq "x86_64") {
    $XBC_REGISTRATION_KEY = "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\TrendMicro\TMSecurityService"
} else {
    $XBC_REGISTRATION_KEY = "HKEY_LOCAL_MACHINE\SOFTWARE\TrendMicro\TMSecurityService"
}
$XBC_DEVICE_ID = reg query "$XBC_REGISTRATION_KEY"
$RETRY_COUNT = 0
$MAX_RETRY = 30
while ($XBC_DEVICE_ID.Length -eq 0) {
    $RETRY_COUNT++
    if ($RETRY_COUNT -ge $MAX_RETRY) {
        Write-Host "$(Get-Date -format T) The agent registration failed. Please see the EndpointBasecamp.log for more details." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "$(Get-Date -format T) The agent is not registered yet. Please wait 10 seconds." -ForegroundColor White
    Start-Sleep -Seconds 10
    $XBC_DEVICE_ID = reg query "$XBC_REGISTRATION_KEY"
}
Write-Host "$(Get-Date -format T) The agent is registered." -ForegroundColor White

## Check SEP is installed and running
$serviceNames = @("tmlisten", "ntrtscan") # tmlisten and ntrtscan is required services for SEP
$MAX_RETRY = 30
$RETRY_DELAY = 10
foreach ($serviceName in $serviceNames) {
    $RETRY_COUNT = 0
    while ($RETRY_COUNT -lt $MAX_RETRY) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                Write-Host "$serviceName is running."
                break
            } else {
                Write-Host "$(Get-Date -format T) Service '$serviceName' is not running yet. Retrying in $RETRY_DELAY seconds..." -ForegroundColor White
            }
        } else {
            Write-Host "$(Get-Date -format T) Service '$serviceName' could not be found. Retrying in $RETRY_DELAY seconds..." -ForegroundColor Yellow
        }
        $RETRY_COUNT++
        Start-Sleep -Seconds $RETRY_DELAY
    }
    if ($RETRY_COUNT -ge $MAX_RETRY) {
        Write-Host "$(Get-Date -format T) Service '$serviceName' did not start after $MAX_RETRY attempts." -ForegroundColor Red
        exit 1
    }
}
Write-Host "$(Get-Date -format T) Standard Endpoint Protection is installed." -ForegroundColor White

Write-Host "$(Get-Date -format T) Finish deploying." -ForegroundColor White
Stop-Transcript
exit 0
</powershell>
