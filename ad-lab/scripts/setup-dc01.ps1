#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Full DC01 provisioning: static IP, AD forest promotion, OUs/groups/users, the
  "Audit Policy - Lab" GPO, DHCP scope. Fired once by autounattend-dc01.xml's
  FirstLogonCommands; re-invokes itself after the forest-promotion reboot via a
  SYSTEM-run scheduled task (not autologon — this has to work headless).

.NOTES
  Mirrors ad-lab/01-domain-setup.md, 02-users-and-groups.md, 03-gpo-hardening.md,
  07-dhcp.md. If those docs and this script ever disagree, the docs describe what
  was actually built by hand first; this script is the from-scratch reproduction —
  update the script to match reality, not the other way round.
#>

param(
    [ValidateSet(1, 2)]
    [int]$Phase = 1
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\Provision\setup-dc01.log"
function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$IfAlias      = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 -ExpandProperty Name)
$StaticIP     = "192.168.100.10"
$Gateway      = "192.168.100.1"
$DomainName   = "lab.local"
$NetbiosName  = "LAB"
$TaskName     = "DC01-Provision-Phase2"

# ---------------------------------------------------------------------------
if ($Phase -eq 1) {
    Log "Phase 1: network config + forest promotion"

    Log "Interface: $IfAlias -> $StaticIP/24 via $Gateway, DNS 127.0.0.1"
    New-NetIPAddress -InterfaceAlias $IfAlias -IPAddress $StaticIP -PrefixLength 24 -DefaultGateway $Gateway -ErrorAction SilentlyContinue
    Set-DnsClientServerAddress -InterfaceAlias $IfAlias -ServerAddresses 127.0.0.1

    Log "Registering scheduled task for phase 2 (runs at startup, as SYSTEM, no interactive logon needed)"
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Provision\setup-dc01.ps1 -Phase 2"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

    Log "Installing AD-Domain-Services"
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null

    # Recovery password: lab-only, thrown away — this forest gets rebuilt from scratch every time,
    # DSRM recovery has never once been needed in this lab's lifetime.
    $safeModePw = ConvertTo-SecureString "DSRM-LabOnly!2026" -AsPlainText -Force

    Log "Install-ADDSForest -DomainName $DomainName -- this reboots the machine"
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -InstallDns `
        -SafeModeAdministratorPassword $safeModePw `
        -Force `
        -NoRebootOnCompletion:$false
    # Execution does not continue past here — the machine reboots. Phase 2 picks up via the
    # scheduled task registered above.
    return
}

# ---------------------------------------------------------------------------
if ($Phase -eq 2) {
    Log "Phase 2: post-promotion configuration"

    Log "Waiting for AD DS services (NTDS, ADWS) to be running"
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 10
        $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
        $adws = Get-Service ADWS -ErrorAction SilentlyContinue
        $ready = ($ntds -and $ntds.Status -eq "Running" -and $adws -and $adws.Status -eq "Running")
    } until ($ready -or (Get-Date) -gt $deadline)
    if (-not $ready) { Log "AD DS services never came up within 10 minutes -- aborting phase 2"; exit 1 }
    Log "AD DS is up"

    Log "Removing the phase-2 scheduled task (one-shot, done its job)"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    Import-Module ActiveDirectory
    Import-Module DnsServer
    $domainDN = (Get-ADDomain).DistinguishedName

    # --- DNS: forwarder + scavenging ---------------------------------------
    Log "DNS forwarder -> 1.1.1.1"
    Add-DnsServerForwarder -IPAddress 1.1.1.1 -ErrorAction SilentlyContinue

    Log "DNS scavenging: 7-day interval, zone aging on"
    Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval "7.00:00:00" -ApplyOnAllZones
    Set-DnsServerZoneAging -ZoneName $DomainName -Aging $true

    # --- OUs -----------------------------------------------------------------
    Log "Creating OUs"
    $ous = "Lab Users", "Workstations", "Servers", "Service Accounts"
    foreach ($ou in $ous) {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $ou -Path $domainDN -ProtectedFromAccidentalDeletion $true
        }
    }

    # --- Department groups -----------------------------------------------------
    Log "Creating department groups (IT, Sales, Finance)"
    foreach ($g in "IT", "Sales", "Finance") {
        if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path "OU=Lab Users,$domainDN"
        }
    }

    # --- 12 test users (ad-lab/scripts/create-users.ps1, copied onto this disk
    #     by the autounattend ISO alongside this script) -----------------------
    Log "Running create-users.ps1"
    if (Test-Path "C:\Provision\create-users.ps1") {
        & "C:\Provision\create-users.ps1"
    } else {
        Log "WARNING: create-users.ps1 not found in C:\Provision -- skipping the 12 test users"
    }

    # --- mmustermann (used in incident-writeups/01-bruteforce.md) --------------
    Log "Creating mmustermann"
    if (-not (Get-ADUser -Filter "SamAccountName -eq 'mmustermann'" -ErrorAction SilentlyContinue)) {
        $pw = ConvertTo-SecureString "Passw0rd!ChangeMe" -AsPlainText -Force
        New-ADUser -Name "Max Mustermann" -GivenName "Max" -Surname "Mustermann" `
            -SamAccountName "mmustermann" -UserPrincipalName "mmustermann@$DomainName" `
            -Path "OU=Lab Users,$domainDN" -AccountPassword $pw -ChangePasswordAtLogon $true -Enabled $true
    }

    # --- svc-sql + SPN (Kerberoasting target) -----------------------------------
    Log "Creating svc-sql with SPN MSSQLSvc/db.lab.local:1433"
    if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc-sql'" -ErrorAction SilentlyContinue)) {
        $pw = ConvertTo-SecureString "Passw0rd!ChangeMe" -AsPlainText -Force
        New-ADUser -Name "svc-sql" -SamAccountName "svc-sql" -UserPrincipalName "svc-sql@$DomainName" `
            -Path "OU=Service Accounts,$domainDN" -AccountPassword $pw -Enabled $true
        setspn -S "MSSQLSvc/db.lab.local:1433" "$NetbiosName\svc-sql" | Out-Null
    }

    # --- Password policy (Default Domain Policy) --------------------------------
    # LockoutThreshold 0 is deliberate, not an oversight -- see ad-lab/03-gpo-hardening.md:
    # it lets the brute-force incident-writeup run without the test account locking itself out.
    Log "Setting default domain password policy"
    Set-ADDefaultDomainPasswordPolicy -Identity $DomainName `
        -ComplexityEnabled $true `
        -MinPasswordLength 12 `
        -MaxPasswordAge "90.00:00:00" `
        -MinPasswordAge "1.00:00:00" `
        -PasswordHistoryCount 24 `
        -ReversibleEncryptionEnabled $false `
        -LockoutThreshold 0

    # --- GPO: "Audit Policy - Lab" -----------------------------------------------
    Log "Creating GPO 'Audit Policy - Lab'"
    Import-Module GroupPolicy
    $gpoName = "Audit Policy - Lab"
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $gpoName }
    New-GPLink -Name $gpoName -Target $domainDN -ErrorAction SilentlyContinue | Out-Null

    # Advanced Audit Policy Configuration (Logon, User Account Management, Process
    # Creation) isn't a registry policy -- it lives in the GPO's own audit.csv under
    # SYSVOL. Set-GPRegistryValue can't write it; this is the actual supported format
    # (same shape `auditpol /backup` produces).
    $gpoPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$($gpo.Id)}\Machine\Microsoft\Windows nt\Audit"
    New-Item -Path $gpoPath -ItemType Directory -Force | Out-Null
    $auditCsv = @"
Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value
,System,Logon,{0CCE9215-69AE-11D9-BED3-505054503030},Success and Failure,,3
,System,User Account Management,{0CCE9235-69AE-11D9-BED3-505054503030},Success and Failure,,3
,System,Process Creation,{0CCE922B-69AE-11D9-BED3-505054503030},Success and Failure,,3
"@
    Set-Content -Path "$gpoPath\audit.csv" -Value $auditCsv -Encoding UTF8

    # SceNoApplyLegacyAuditPolicy: tells the client to honor audit.csv instead of the
    # legacy 9-category audit policy -- this is the registry side of "Advanced Audit
    # Policy Configuration" and IS settable via Set-GPRegistryValue.
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
        -ValueName "SCENoApplyLegacyAuditPolicy" -Type DWord -Value 1 | Out-Null

    Log "Setting registry-based policies in the same GPO (cmdline logging, USB block, inactivity lock, PS logging)"
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" `
        -ValueName "ProcessCreationIncludeCmdLine_Enabled" -Type DWord -Value 1 | Out-Null

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices" `
        -ValueName "Deny_All" -Type DWord -Value 1 | Out-Null

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "InactivityTimeoutSecs" -Type DWord -Value 900 | Out-Null

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
        -ValueName "EnableScriptBlockLogging" -Type DWord -Value 1 | Out-Null

    # Writing audit.csv alone is NOT enough: clients only process it if the GPO's AD object
    # lists the "Audit Policy Configuration" client-side extension in gPCMachineExtensionNames.
    # GPMC adds that automatically, a plain file write doesn't -- found 2026-10-10, when the
    # rebuilt lab had no Process Creation auditing (no 4688 events) on either machine.
    # Done after the Set-GPRegistryValue calls so the list stays sorted by CSE GUID
    # (registry {35378EAC...} before audit {F3CCC681...}).
    $gpoDN = "CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
    $auditCse = "[{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]"
    $ext = (Get-ADObject $gpoDN -Properties gPCMachineExtensionNames).gPCMachineExtensionNames
    if ($ext -notmatch "F3CCC681") {
        Set-ADObject $gpoDN -Replace @{gPCMachineExtensionNames = "$ext$auditCse"}
        # Bump the GPO version (AD + GPT.INI together) so clients reprocess it
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
            -ValueName "SCENoApplyLegacyAuditPolicy" -Type DWord -Value 1 | Out-Null
    }

    # --- Department shares (ad-lab/05-fileserver-acls.md) ----------------------
    # Share permission wide open, NTFS does the real restricting: inheritance off,
    # only the matching department group + Domain Admins.
    Log "Creating department shares IT/Sales/Finance with NTFS ACLs"
    foreach ($dept in "IT","Sales","Finance") {
        $path = "C:\Shares\$dept"
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        if (-not (Get-SmbShare -Name $dept -ErrorAction SilentlyContinue)) {
            New-SmbShare -Name $dept -Path $path -FullAccess "Everyone" | Out-Null
        }
        $acl = Get-Acl $path
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$NetbiosName\$dept","Modify","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$NetbiosName\Domain Admins","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        Set-Acl $path $acl
    }

    # --- DNS beyond the basics (ad-lab/09-dns-deep-dive.md) ---------------------
    Log "Adding CNAME/MX/TXT records"
    $zone = $DomainName
    if (-not (Get-DnsServerResourceRecord -ZoneName $zone -Name "fileserver" -RRType CName -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecordCName -ZoneName $zone -Name "fileserver" -HostNameAlias "dc01.$DomainName"
    }
    if (-not (Get-DnsServerResourceRecord -ZoneName $zone -Name "@" -RRType MX -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecordMX -ZoneName $zone -Name "@" -MailExchange "dc01.$DomainName" -Preference 10
    }
    if (-not (Get-DnsServerResourceRecord -ZoneName $zone -Name "@" -RRType Txt -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecord -ZoneName $zone -Txt -Name "@" -DescriptiveText "v=spf1 -all"
    }

    # Zone transfers only to servers listed in the zone's NS records (= nobody here).
    Set-DnsServerPrimaryZone -Name $zone -SecureSecondaries TransferToZoneNameServer

    # Split-horizon for portal.lab.local. The -Fqdn condition is mandatory: without it the
    # policies apply to the WHOLE zone and every other name resolves NXDOMAIN (see 09-dns-deep-dive.md).
    Log "Creating split-horizon zone scopes + policies for portal.$DomainName"
    foreach ($scope in @(@{Name="InternalScope"; IP="192.168.100.20"}, @{Name="ExternalScope"; IP="203.0.113.50"})) {
        if (-not (Get-DnsServerZoneScope -ZoneName $zone -Name $scope.Name -ErrorAction SilentlyContinue)) {
            Add-DnsServerZoneScope -ZoneName $zone -Name $scope.Name
        }
        if (-not (Get-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope.Name -Name "portal" -ErrorAction SilentlyContinue)) {
            Add-DnsServerResourceRecord -ZoneName $zone -A -Name "portal" -IPv4Address $scope.IP -ZoneScope $scope.Name
        }
    }
    if (-not (Get-DnsServerClientSubnet -Name "InternalSubnet" -ErrorAction SilentlyContinue)) {
        Add-DnsServerClientSubnet -Name "InternalSubnet" -IPv4Subnet "192.168.100.0/24"
    }
    if (-not (Get-DnsServerClientSubnet -Name "ExternalSubnet" -ErrorAction SilentlyContinue)) {
        Add-DnsServerClientSubnet -Name "ExternalSubnet" -IPv4Subnet "0.0.0.0/0"
    }
    foreach ($p in @(@{Name="InternalPolicy"; Subnet="InternalSubnet"; Scope="InternalScope"},
                     @{Name="ExternalPolicy"; Subnet="ExternalSubnet"; Scope="ExternalScope"})) {
        if (-not (Get-DnsServerQueryResolutionPolicy -ZoneName $zone -Name $p.Name -ErrorAction SilentlyContinue)) {
            Add-DnsServerQueryResolutionPolicy -Name $p.Name -Action ALLOW -ZoneName $zone `
                -ClientSubnet "eq,$($p.Subnet)" -Fqdn "eq,portal.$DomainName" -ZoneScope "$($p.Scope),1"
        }
    }

    # --- DHCP ------------------------------------------------------------------
    Log "Installing DHCP role and authorizing in AD"
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    Add-DhcpServerInDC -DnsName "dc01.$DomainName" -IPAddress $StaticIP -ErrorAction SilentlyContinue

    Log "Creating DHCP scope 192.168.100.100-200"
    if (-not (Get-DhcpServerv4Scope -ScopeId 192.168.100.0 -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Scope -Name "Lab-Network" -StartRange 192.168.100.100 -EndRange 192.168.100.200 `
            -SubnetMask 255.255.255.0 -State Active
    }
    Set-DhcpServerv4OptionValue -ScopeId 192.168.100.0 -Router $Gateway -DnsServer $StaticIP -DnsDomain $DomainName

    Log "gpupdate /force"
    gpupdate /force /target:computer | Out-Null

    Log "Phase 2 complete. DC01 provisioning done -- next step is WS01 (setup-ws01.ps1)."
}
