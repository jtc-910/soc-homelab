#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Installs Sysmon (SwiftOnSecurity config) and the Wazuh agent, then adds the two
  <localfile> eventchannel blocks Wazuh needs to actually forward Sysmon and
  PowerShell operational logs -- installing the agent alone does not do this.
  Run on both DC01 and WS01, after they're domain-joined (WS01) / promoted (DC01).

.NOTES
  client.keys from the old lab is deliberately NOT reused here -- both machines are
  new installs, clean enrollment against the new manager is the more honest state.
  See docker-lab/scripts/restore-stacks.sh and the migration plan's Phase E notes for
  the old client.keys, kept only as a local rollback reference.

  Localfile blocks: configs/wazuh-agent-sysmon.ossec.conf.snippet (same repo).
  GPO PowerShell Script Block Logging is what makes the second block (4104 events)
  actually produce data -- see ad-lab/03-gpo-hardening.md for why both are needed.
#>

param(
    [string]$WazuhManagerIP = "192.168.100.30",
    [string]$WazuhVersion   = "4.14.7"
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\Provision\install-sysmon-wazuh-agent.log"
function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$WorkDir = "C:\Provision\downloads"
New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null

# --- Sysmon --------------------------------------------------------------------
Log "Downloading Sysmon"
$sysmonZip = "$WorkDir\Sysmon.zip"
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile $sysmonZip
Expand-Archive -Path $sysmonZip -DestinationPath "$WorkDir\Sysmon" -Force

Log "Downloading SwiftOnSecurity Sysmon config"
$sysmonConfig = "$WorkDir\sysmonconfig-export.xml"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -OutFile $sysmonConfig

if (-not (Get-Service Sysmon64 -ErrorAction SilentlyContinue)) {
    Log "Installing Sysmon"
    & "$WorkDir\Sysmon\Sysmon64.exe" -accepteula -i $sysmonConfig | Out-String | ForEach-Object { Log $_ }
} else {
    Log "Sysmon already installed, updating config"
    & "$WorkDir\Sysmon\Sysmon64.exe" -accepteula -c $sysmonConfig | Out-String | ForEach-Object { Log $_ }
}

# --- Wazuh agent -----------------------------------------------------------------
Log "Downloading Wazuh agent $WazuhVersion"
$wazuhMsi = "$WorkDir\wazuh-agent-$WazuhVersion.msi"
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion-1.msi" -OutFile $wazuhMsi

Log "Installing Wazuh agent, manager=$WazuhManagerIP"
Start-Process msiexec.exe -ArgumentList @(
    "/i", "`"$wazuhMsi`"",
    "/q",
    "WAZUH_MANAGER=`"$WazuhManagerIP`"",
    "WAZUH_REGISTRATION_SERVER=`"$WazuhManagerIP`""
) -Wait

$agentConf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
$deadline = (Get-Date).AddMinutes(2)
while (-not (Test-Path $agentConf) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
if (-not (Test-Path $agentConf)) { Log "ERROR: ossec.conf not found after install, aborting"; exit 1 }

# --- Add the eventchannel localfile blocks --------------------------------------
Log "Adding Sysmon + PowerShell eventchannel <localfile> blocks to agent ossec.conf"
[xml]$xml = Get-Content $agentConf

function Add-LocalfileIfMissing($xml, $location) {
    $exists = $xml.ossec_config.localfile | Where-Object { $_.location -eq $location }
    if ($exists) { return }
    $lf = $xml.CreateElement("localfile")
    $loc = $xml.CreateElement("location"); $loc.InnerText = $location
    $fmt = $xml.CreateElement("log_format"); $fmt.InnerText = "eventchannel"
    $lf.AppendChild($loc) | Out-Null
    $lf.AppendChild($fmt) | Out-Null
    $xml.ossec_config.AppendChild($lf) | Out-Null
}

Add-LocalfileIfMissing $xml "Microsoft-Windows-Sysmon/Operational"
Add-LocalfileIfMissing $xml "Microsoft-Windows-PowerShell/Operational"
$xml.Save($agentConf)

Log "Restarting WazuhSvc"
Restart-Service -Name WazuhSvc

Log "Done. Verify from the manager: docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -l"
