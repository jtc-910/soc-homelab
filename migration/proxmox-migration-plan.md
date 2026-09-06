# Homelab-Migration MacBook/UTM (ARM64) → Intel i9 / Proxmox VE (x86_64)
## Automatisierter Durchlauf mit Meilenstein-Gates

## Context

Das SOC-Homelab läuft auf einem MacBook Pro M1 Pro (16 GB) unter UTM/QEMU, alle VMs sind
ARM64 — inklusive Windows Server 2025 als **inoffizieller Insider-Build 26404 aus einem
Community-Mirror**, weil Microsoft für ARM keinen regulären Server-Download anbietet
([00-lab-setup.md](../00-lab-setup.md)). Das Lab steht an einer dokumentierten RAM-Wand:
Wazuh-Manager + Indexer + Dashboard + TheHive/Cortex + Cassandra + Elasticsearch + DVWA/
Juice Shop auf einer VM treiben den freien Speicher in den zweistelligen MiB-Bereich, Swap
ist aktiv, DVWA lief im OOM-Crashloop
([docker-lab/04-thehive-cortex.md:257-269](../docker-lab/04-thehive-cortex.md#L257-L269)).

Ein Intel-i9-Desktop (32 GB RAM, mehrere SSDs, die 1-TB-Ubuntu-SSD darf gewiped werden)
übernimmt das Lab. Damit wird die in
[PORTFOLIO_ROADMAP.md:650-670](../PORTFOLIO_ROADMAP.md#L650-L670) notierte Idee umgesetzt.

**Betriebsmodus dieses Plans:** Claude führt aus, Jonas bestätigt an Meilensteinen. Alles,
was ohne physischen Zugriff geht, wird per SSH/Skript automatisiert. Der einzige
Handgriff ist die Proxmox-Installation selbst (~15 Min, Bare-Metal-Installer).

**Zielzustand:** Proxmox VE bare metal, alle Lab-VMs nativ x86_64 aus offiziellen ISOs,
isoliertes `192.168.100.0/24` per NAT-Bridge, Zugriff vom Mac ausschließlich remote.

---

## Architekturentscheidung: Proxmox VE (bare metal)

**Framing-Korrektur:** Proxmox VE ist keine „Ubuntu-VM" und läuft auch nicht *auf* Ubuntu.
Es ist ein Debian-basiertes Host-OS, das die Maschine übernimmt. „Ubuntu Server + KVM" und
„Proxmox VE" sind **Alternativen für dieselbe Kiste**, keine Schichten.

Gewählt: **Proxmox VE 9.x, x86_64-ISO** (die ARM64/Armv9-Notiz in der Roadmap ist
gegenstandslos). Begründung: Snapshots als First-Class-Feature inkl. RAM-State, Web-Konsole
ohne Client-Setup (entscheidend bei headless), `vzdump` eingebaut, und LXC für Pi-hole bzw.
VM+PCIe-Passthrough für pfSense später. Der Nachteil — Proxmox will die Maschine für sich —
ist hier keiner, der Rechner soll ohnehin headless 24/7 laufen.

`docker01` wird als **VM** neu gebaut, nicht als LXC: Docker-in-LXC braucht
Nesting/keyctl-Gefummel und ist die falsche Art von „interessant" fürs Portfolio.

**pfSense bleibt draußen.** Das Internet der Wohnung an dieselbe Kiste zu hängen, auf der
Snapshots und Rollbacks getestet werden, koppelt Familien-Uptime an Lab-Experimente.
Eigenes Projekt, nach der Migration.

### Zielbelegung (32 GB RAM, 1 TB SSD, thin-provisioned)

| VM | OS (x86_64, offizielle ISO) | IP | RAM | vCPU | Disk |
|---|---|---|---|---|---|
| `docker01` | Ubuntu Server LTS amd64 (Cloud-Image) | `192.168.100.30` | **14 GB** | 6 | 120 GB |
| `DC01` | Windows Server 2025 Standard (Desktop Exp.) | `192.168.100.10` | 6 GB | 4 | 80 GB |
| `WS01` | Windows 11 **Pro** | `192.168.100.20` | 6 GB | 4 | 80 GB |
| `kali` | *zurückgestellt, siehe unten* | `192.168.100.40` | 4 GB | 4 | 60 GB |

Basis-Set = 26 GB + ~3 GB Host = 29 GB. Erstmals laufen alle drei komfortabel gleichzeitig.
Die 14 GB für `docker01` sind der eigentliche Payoff — die dokumentierte Fragilität aus
[docker-lab/04-thehive-cortex.md](../docker-lab/04-thehive-cortex.md) verschwindet ersatzlos.

> **Kali zurückgestellt.** In UTM existiert bereits eine `Kali Linux.utm`, obwohl die
> Roadmap sie als „geplant" führt. Ein vierter OS-Install verlängert einen ohnehin langen
> Lauf; Kali ist Phase-3-Material (Roadmap 1.9/1.12) und wird nach der Migration separat
> gebaut. Die VM-Definition wird vorbereitet, aber nicht installiert.

---

## Migrieren vs. neu aufsetzen

ARM64-qcow2-Images sind **nicht** übertragbar — ein Gast-OS-Image trägt Kernel und Userland
der Ziel-Architektur. Alle VMs werden aus offiziellen x86-ISOs neu installiert. Das ist kein
Verlust, sondern der Hauptgewinn: der unoffizielle Server-Insider-Build fliegt raus.

| Übertragbar | Nicht übertragbar |
|---|---|
| Docker-Named-Volumes (Wazuh, Cassandra, Elasticsearch) | VM-Disk-Images |
| Compose-Files inkl. hand-editierter Passwörter | TLS-Zertifikate (werden neu generiert) |
| Custom Wazuh-Rules + Decoders | Sysmon-Binary (`Sysmon64a.exe` → `Sysmon64.exe`) |
| `custom-w2thive` + `.py` | AD-Datenbank |
| Die Doku als Blueprint für AD/GPO/Users | |

---

## ⚠️ Kernrisiko: die Config existiert nur auf einer Disk

Das Repo enthält **null lauffähige Konfiguration**. Keine `docker-compose.yml`, kein `.env`,
keine Rule-XML. Ausschließlich auf der `docker01`-Disk liegen:

- `~/wazuh-docker/single-node/docker-compose.yml` mit hand-editiertem `INDEXER_PASSWORD`
- `config/wazuh_indexer/internal_users.yml` mit hand-eingefügtem bcrypt-Hash
- `/var/ossec/etc/rules/` + `/var/ossec/etc/decoders/` — **nirgendwo sonst dokumentiert**
- der `<integration>`-Block in `ossec.conf` mit dem echten TheHive-API-Key
- die StrangeBee-Compose-Konfiguration (`docker-thehive4`, Profil `testing`)

Stirbt diese Disk mitten in der Migration, ist das AD-Lab aus der Doku rekonstruierbar —
das SIEM-Tuning nicht. **Phase A endet deshalb erst, wenn das redigiert im Git liegt.**
Nebeneffekt: schließt eine echte Portfolio-Lücke — ein Detection-Engineering-Repo ohne die
Detections darin ist unvollständig.

---

## Voraussetzungen (blockierend, vor Phase A)

1. **SSH-Zugang zu `docker01`.** Ich starte die VM per
   `/Applications/UTM.app/Contents/MacOS/utmctl start "Ubuntu Server"` — aber ohne
   Credentials komme ich nicht hinein. `~/.ssh/` ist leer. Benötigt: Username, und einmalig
   das Passwort (ich lege danach sofort einen SSH-Key an, dann läuft alles ohne Nachfragen).
2. **Windows Server 2025 Eval-ISO.** Das MS Evaluation Center verlangt ein
   Registrierungsformular — `curl` kommt da nicht durch. **Bitte parallel im Browser
   starten** (x64, Standard, Desktop Experience) nach `~/Downloads/`; ~5 GB, kostet dich
   einen Klick und blockiert sonst später die komplette AD-Phase. Windows 11 x64 und Ubuntu
   Cloud-Image lade ich selbst.
3. **Proxmox VE 9.x ISO** — lade ich, du schreibst den Stick.

---

## Phase A — Extraktion & Vorbereitung (Mac, ohne i9)

Der i9 ist aus. Diese Phase läuft komplett auf dem MacBook.

**A1** `docker01` per `utmctl` starten, SSH-Key einrichten, Verbindung verifizieren.

**A2 Inventarisieren** — die Volume-Namen sind im Repo nirgends dokumentiert, nicht raten:
```bash
docker volume ls && docker ps -a
cd ~/wazuh-docker/single-node && docker compose config
cd ~/docker-thehive4 && docker compose config
docker inspect single-node-wazuh.manager-1 --format '{{json .Mounts}}' | jq
```

**A3 Configs & Secrets sichern** nach `~/migration-export/`:
- beide `docker-compose.yml` + `.env` + `internal_users.yml`
- `docker cp` aus dem Manager: `/var/ossec/etc/{rules,decoders,ossec.conf,client.keys}`
- `/var/ossec/integrations/custom-w2thive` + `custom-w2thive.py`
  (Fallback: Volltext in [docker-lab/04-thehive-cortex.md:59-165](../docker-lab/04-thehive-cortex.md#L59-L165))

**A4 Volumes als Tarballs** — Container vorher stoppen, sonst sind Cassandra- und
Elasticsearch-Archive korrupt:
```bash
docker compose stop
docker run --rm -v <volume>:/data -v ~/migration-export:/backup alpine \
  tar czf /backup/<volume>.tar.gz -C /data .
```

**A5** Alles per rsync auf den Mac nach `~/HOMELAB/migration-export/`.

**A6 Ins Repo committen (redigiert)** — Compose-Files mit Platzhaltern, Rules/Decoders im
Klartext, Skripte mit `<API_KEY>`-Platzhalter, nach `docker-lab/configs/`. `.gitignore`
deckt `secrets*`, `*.key`, `*.pem` bereits ab; Klartext-Secrets bleiben lokal.
**Im selben Commit:** [docker-lab/03-dvwa-juiceshop.md](../docker-lab/03-dvwa-juiceshop.md) —
noch uncommitted, und dieses Markdown ist die einzige Kopie des `pentest`-Compose-Blocks.

**A7 Provisioning-Artefakte schreiben** (ins Repo, nicht als „Befehle die ich später tippe"):
- `ad-lab/scripts/autounattend-dc01.xml`, `autounattend-ws01.xml` — vollautomatische
  Windows-Installation ohne einen Klick
- `ad-lab/scripts/setup-dc01.ps1` — Netz, `Install-ADDSForest`, DNS-Forwarder, Scavenging,
  DHCP-Scope, OUs, Gruppen, GPO `Audit Policy - Lab`, Passwort-Policy
- `ad-lab/scripts/setup-ws01.ps1` — Netz, Domain-Join
- `ad-lab/scripts/install-sysmon-wazuh-agent.ps1` — Sysmon + Agent + die beiden
  `<localfile>`-Blöcke aus
  [configs/wazuh-agent-sysmon.ossec.conf.snippet](configs/wazuh-agent-sysmon.ossec.conf.snippet)
- `docker-lab/scripts/restore-stacks.sh` — Volumes zurückspielen, Stacks hochfahren
- `proxmox/` — `interfaces`-Snippet, cloud-init für `docker01`, VM-Create-Skripte

  > Diese Artefakte sind gleichzeitig die **Resume-Fähigkeit**: Bricht die Session ab,
  > lautet der nächste Schritt „Skript N+1 ausführen", nicht „rekonstruieren, was Claude
  > gerade tat". Und sie machen den Lauf reproduzierbar — dasselbe Portfolio-Argument wie
  > bei den Rules.

**A8** Proxmox-ISO + Windows-11-ISO + Ubuntu-Cloud-Image laden.

> **🚦 Meilenstein 1** — Extraktion liegt **committed im Git**, alle Skripte geschrieben,
> ISOs da. Ab hier ist der wertvollste Teil unverlierbar. Ich zeige dir das Ergebnis und
> gebe dir die Proxmox-Installationscheckliste.

---

## Phase B — Proxmox installieren (dein Teil, ~15 Min)

Bewusst **keine** Auto-Install-ISO: `proxmox-auto-install-assistant` ist ein
x86-Debian-Tool, der Mac ist ARM ohne Docker. Eine Toolchain zu bauen, um 10 Minuten
Klicks zu sparen, ist der schlechtere Deal. Du bekommst stattdessen eine Checkliste mit
allen Werten zum Abtippen.

1. ISO auf USB schreiben (mache ich per `dd`, du steckst nur den Stick ein).
2. Monitor + Tastatur an den i9, von USB booten. **Im BIOS/UEFI prüfen: VT-x und VT-d
   aktiv** — ohne die läuft keine VM performant.
3. Zielplatte: die **1-TB-SSD**. Andere SSDs im Installer nicht anfassen.
4. Dateisystem **ext4 + LVM-Thin** (Default). ZFS erst ab RAID sinnvoll und frisst RAM.
5. Netzwerk: statische IP im `192.168.178.0/24`-Netz (Vorschlag `192.168.178.50`),
   Gateway `192.168.178.1`, exakte Werte kommen aus Meilenstein 1.
6. Nach dem Reboot **Monitor abklemmen** — alles Weitere übernehme ich.

> **🚦 Meilenstein 2** — du sagst „läuft", ich übernehme per SSH.

---

## Phase C — Host-Setup & Netzwerk (automatisiert)

**C1** SSH-Key, Enterprise-Repo aus, `pve-no-subscription` an, `apt dist-upgrade`,
`genisoimage`/`xorriso` nachinstallieren. SSH-Hardening analog
[linux-lab/01-ssh-hardening.md](../linux-lab/01-ssh-hardening.md).

**C2** Weitere SSDs einbinden: LVM-Thin für VM-Disks, Directory-Storage für `vzdump` und
das Migrationsarchiv.

**C3 `migration-export` sofort hochschieben** — der Host hängt am Heimnetz und ist trivial
erreichbar, die spätere `docker01` hinter `vmbr1` nicht. Wichtiger als Bequemlichkeit: die
Rules/Decoders liegen damit auf der neuen Kiste, *bevor* der Umbau beginnt.

**C4 Netzwerk — das UTM-„Shared Network" nachbauen.** Ziel-Verhalten identisch zu heute:
VMs sehen sich, haben Internet, sind vom Heimnetz unsichtbar. Das Äquivalent ist eine
**Linux-Bridge ohne physischen Port + NAT/Masquerade** — *nicht* an `eno1` gebridgt, das
höbe die Isolation auf.

```
auto vmbr0                       # Heimnetz, trägt die Web-UI
iface vmbr0 inet static
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

auto vmbr1                       # isoliertes Lab-Netz
iface vmbr1 inet static
    address 192.168.100.1/24
    bridge-ports none            # <- kein physischer Port = Isolation
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o vmbr0 -j MASQUERADE
```

**Gateway `.15` → `.1`:** `192.168.100.15` war ein reines UTM-Artefakt (dessen
DHCP-*Start*-Adresse, die zugleich als Gateway diente). Der Wechsel auf `.1` **behebt
zugleich einen latenten Bug**: DC01s DHCP-Scope verteilt laut
[ad-lab/07-dhcp.md:51](../ad-lab/07-dhcp.md#L51) bereits `-Router 192.168.100.1` — eine
Adresse, die es heute gar nicht gibt. Danach stimmt sie.
*Kollisionsprüfung erledigt:* Heimnetz ist `192.168.178.0/24`.

**Kein DHCP auf `vmbr1`** — alle Lab-Hosts sind statisch, DC01s Scope `.100`–`.200` ist
danach die einzige DHCP-Instanz im Segment. Sauberer als heute (UTM `.15`–`.50` *und*
DC01s Scope konkurrieren).

**C5 Isolationstest:** Wegwerf-VM `.99` an `vmbr1` — muss `192.168.100.1` pingen, ins
Internet kommen, und vom Mac aus **nicht** erreichbar sein.

> **Wenn `ping 192.168.100.1` klappt, `ping 1.1.1.1` aber nicht:** erster Verdächtiger ist
> der Firewall-Backend. PVE 9 bringt neben iptables eine nftables-basierte Firewall
> (`proxmox-firewall`) mit, die sich mit handgeschriebenen NAT-Regeln beißen kann. Managed
> Fallback: **SDN → Zone-Typ „Simple"**. Die manuelle Bridge bleibt erste Wahl —
> transparenter und besseres Material für den Writeup.

**C6 Fernzugriff einrichten:** `~/.ssh/config` auf dem Mac mit `ProxyJump` über den Host
(das Lab-Netz ist vom Heimnetz aus unsichtbar, der Host ist der einzige Weg hinein);
Portforward-Aliase für Wazuh-Dashboard/TheHive/DVWA.

---

## Phase D — `docker01` (automatisiert)

> **Korrektur zur ursprünglich vorgeschlagenen Reihenfolge:** „erst Docker-Lab rüberziehen,
> danach Wazuh-VM neu aufsetzen" sind keine zwei Schritte. Wazuh *ist* Docker auf
> `docker01` — dieselbe Box, nur umbenannt (`hostnamectl set-hostname docker01`, vorher
> `wazuh`, [docker-lab/01-docker-intro.md:24-46](../docker-lab/01-docker-intro.md#L24-L46)).
> Der Instinkt „das Wiederherstellbarste zuerst" ist richtig, die Prämisse nicht.
> `docker01` zuerst validiert außerdem die NAT-Bridge, *bevor* Stunden ins AD fließen.

1. Ubuntu-Cloud-Image + cloud-init — statisch `192.168.100.30/24`, GW `.1`, SSH-Key,
   Docker vorinstalliert. Kein Installer, keine Klicks. Volle Disk wird sofort geclaimt
   (Ubuntus Installer nimmt sonst nur die Hälfte,
   [99-troubleshooting.md:51-62](../99-troubleshooting.md#L51-L62)).
2. **UFW-Lücke schließen:** Die Regeln stammen aus der nativen Installation und decken
   8080/3000/8443 nicht ab — und Dockers publizierte Ports fügen iptables-Regeln *vor* UFW
   ein. Ports an `127.0.0.1` binden oder `DOCKER-USER`-Chain nutzen.
3. **Wazuh-Stack:** `wazuh-docker` auf `v4.14.7` klonen (identischer Tag), **Zertifikate
   neu generieren** (nicht die alten kopieren), Compose + `internal_users.yml` einspielen,
   Volumes zurückschreiben, hochfahren.
4. **TheHive/Cortex:** StrangeBee-Repo, Profil `testing`, Cassandra-/ES-Volumes zurück.
   Integrationsskripte per `docker cp`, `chown root:wazuh`, `chmod 750`.
   **`thehive4py 2.1.0`** in die Python-Umgebung des Manager-Containers nachinstallieren —
   liegt auf keinem Volume und ist bei jedem Recreate weg.
   TheHive→Cortex über `http://cortex:9001/cortex`, nicht die Browser-URL.

   > **Kopplung:** Der gesicherte TheHive-API-Key funktioniert nur zusammen mit *diesem*
   > Cassandra-Volume — der Key liegt in dieser Datenbank. Scheitert der Restore und
   > TheHive wird frisch aufgesetzt, ist der Key ungültig: neuen in der UI erzeugen und den
   > `<integration>`-Block in `ossec.conf` anpassen, **bevor** man Alerts erwartet. Sonst
   > ist der Wazuh→TheHive-Pfad still kaputt.
5. **DVWA/Juice Shop:** Compose mit `pentest`-Profil. **Der `tonistiigi/binfmt`-Hack
   entfällt ersatzlos** — DVWA ist amd64-only und läuft jetzt nativ statt emuliert.
6. Proxmox-Snapshot.

> **🚦 Meilenstein 3** — Dashboard erreichbar, Indexer grün, kein Restart-Loop,
> `free -h` zeigt reichlich Luft.

---

## Phase E — AD-Lab (automatisiert, ein Stück)

Bewusst **kein Gate mittendrin**: Installation → Promotion → Reboots → GPOs ist ein
atomarer Abschnitt; ein Halt zwischen Promotion und GPO-Anwendung hinterlässt eine Domain
in einem unangenehm zu beurteilenden Zustand.

1. **`autounattend.xml` als eigene Mini-ISO** auf dem Proxmox-Host bauen
   (`genisoimage`) und als zweites CD-ROM anhängen — Windows Setup durchsucht
   Wechselmedien danach. **Kein Umbau der Windows-ISO auf dem Mac.**
2. **`DC01`:** Windows Server 2025 Standard, Desktop Experience, **offizielle x64-Eval-ISO**.
   Der unoffizielle ARM-Insider-Build 26404 wird nicht mehr gebraucht — das entfernt den
   einzigen echten Supply-Chain-Makel des Labs. Eval läuft 180 Tage.
   VirtIO-Treiber-ISO als drittes Laufwerk; Fallback SATA + `e1000`.
3. `setup-dc01.ps1`: statisch `.10`, DNS `127.0.0.1`,
   `Install-ADDSForest -DomainName "lab.local" -DomainNetbiosName "LAB" -InstallDns`,
   Forwarder `1.1.1.1`, Scavenging, DHCP-Scope `.100`–`.200` mit **`-Router 192.168.100.1`**
   (jetzt korrekt), 4 OUs, Gruppen IT/Sales/Finance,
   [ad-lab/scripts/create-users.ps1](../ad-lab/scripts/create-users.ps1) plus `mmustermann`
   und `svc-sql` inkl. SPN `MSSQLSvc/db.lab.local:1433`, GPO `Audit Policy - Lab`
   (Logon, User Account Management, Process Creation inkl. Command Line, USB-Block,
   900s Inactivity, Script Block Logging), Passwort-Policy inkl. `LockoutThreshold 0`.
   **Die `0x8007000B`-Falle entfällt** — die trat nur bei x64-emuliertem PowerShell auf
   Windows-on-ARM auf ([99-troubleshooting.md:20-36](../99-troubleshooting.md#L20-L36)).
4. **`WS01`:** Windows 11 **Pro** x64 (Home kann nicht joinen), statisch `.20`, DNS `.10`,
   Domain-Join. Ohne Key unaktiviert — fürs Lab unkritisch.
5. **Sysmon + Wazuh-Agent** auf beiden: `Sysmon64.exe` (nicht mehr `Sysmon64a.exe`) mit
   SwiftOnSecurity-Config, Enrollment gegen `.30`, **beide `<localfile>`-Blöcke** —
   ohne den PowerShell-Eventchannel kommen 4104-Events nie am SIEM an, das war schon
   einmal eine echte Lücke.
   `client.keys` wird *nicht* wiederverwendet: die Maschinen sind neu, sauberes Enrollment
   ist der ehrlichere Weg. Die Datei bleibt nur als Rollback-Option.
6. Snapshots nach jedem Meilenstein innerhalb der Phase.
7. **Abschluss-Gate dieser Phase ist der Brute-Force-Replay** aus
   [incident-writeups/01-bruteforce.md](../incident-writeups/01-bruteforce.md) — nicht erst
   am Ende der Doku-Phase. Er testet als einziger, ob ein echtes Event den Weg
   Agent → Manager → Custom-Rule → Alert → TheHive-Case geht. Schlägt er fehl, liegt die
   Ursache in der AD-Audit-Config oder den `<localfile>`-Blöcken — also exakt in dem, was
   gerade gebaut wurde. `docker compose ps` grün und `wazuh-logtest` sind *nicht* dasselbe.

> **🚦 Meilenstein 4** — Domain steht, WS01 gejoined, beide Agents Active,
> Brute-Force-Kette läuft end-to-end.

---

## Phase F — Validierung, Doku, Rückbau

1. **[04-validation.md](../04-validation.md) komplett durchlaufen** — die Tests stehen schon
   geschrieben, sie sind das objektive Abnahmekriterium.
2. **Doku aktualisieren** (Teil der Migration, nicht danach):
   - [README.md](../README.md): Maschinen-Tabelle (alle Zeilen sagen ARM64),
     „Apple Silicon ARM64"-Badge in Zeile 11
   - [00-lab-setup.md](../00-lab-setup.md): UTM → Proxmox, ISO-Quellen auf offizielle x64;
     `docker01`-RAM korrigieren (README sagt 4 GB, real waren ~9,2 GiB — nie dokumentiert)
   - [99-troubleshooting.md](../99-troubleshooting.md): UTM-/ARM-Einträge als „historisch,
     gelöst durch Migration" markieren statt löschen — die Fehlersuche ist Portfolio-Substanz
   - [assets/diagrams/network-diagram.drawio](assets/diagrams/network-diagram.drawio) + `.svg`
     neu (Gateway `.1`, Proxmox statt UTM)
   - [PORTFOLIO_ROADMAP.md](../PORTFOLIO_ROADMAP.md): Migration als erledigt; blockierte Punkte
     (1.9 dedicated segment, 1.12 tcpdump, 1.10 split-horizon) als entblockt markieren
   - **Neu:** `docker-lab/05-hardware-migration.md` — eine ARM→x86-Migration mit
     Volume-Erhalt ist ein besseres Portfolio-Stück als die meisten offenen Roadmap-Punkte
3. **UTM bleibt unangetastet**, bis `04-validation.md` vollständig grün ist. Objektives
   Gate statt Bauchgefühl. Danach `docker01` als letztes löschen. UTM selbst kann als
   Sandbox bleiben; das Lab zieht komplett um.

---

## Reihenfolge & Resume

```
A. Extraktion + Skripte (Mac)     ── ohne i9; endet mit Commit im Git
   🚦 M1
B. Proxmox-Install (deine 15 Min) ── einziger physischer Handgriff
   🚦 M2
C. Host + Netzwerk + Isolationstest
D. docker01 (Wazuh + TheHive + Targets — eine Box)
   🚦 M3
E. DC01 → WS01 → Agents → Brute-Force-Replay
   🚦 M4
F. Validierung → Doku → Rückbau
```

**Wenn die Session mittendrin endet:** Jede Phase hinterlässt Dateien, keine offenen
Gedanken. Phase A → Commit im Repo + `~/HOMELAB/migration-export/`. Phase C–E → alle
Skripte liegen in `proxmox/`, `ad-lab/scripts/`, `docker-lab/scripts/` auf dem Host.
Wiederaufnahme heißt „Skript N+1 ausführen".

## Verifikation

| Nach | Test | Erwartung |
|---|---|---|
| A | `git log` + `ls docker-lab/configs/` | Rules, Decoders, Compose redigiert im Repo |
| C | Test-VM `.99`: `ping .1`, `ping 1.1.1.1`; vom Mac `ping 192.168.100.99` | erste zwei ok, letzter **schlägt fehl** |
| C | Web-UI `:8006` + `ssh docker01` vom Mac | beides ohne Monitor am i9 |
| D | `docker compose ps`, Dashboard per Portforward, `free -h` | alles Up, kein Restart-Loop, > 4 GB frei |
| E | `Get-ADDomain`, `Get-ADUser -Filter *`, `gpresult /r` | 12+ User, GPO angewendet |
| E | `agent_control -l` | DC01 + WS01 **Active** |
| E | **Brute-Force-Replay → TheHive-Case** | End-to-End-Kette, inkl. Custom-Rules |
| F | [04-validation.md](../04-validation.md) | alle Checks grün → UTM darf weg |

## Offene Punkte

- **Blockierend:** `docker01`-SSH-Credentials (Username + einmalig Passwort).
- **Parallel starten:** Windows Server 2025 Eval-ISO im Browser herunterladen.
- Volume-Namen sind unbekannt — A2 liefert sie, Restore-Befehle erst danach final.
- SSD-Ausstattung des i9 wird bei erstem SSH-Zugriff inventarisiert (`lsblk`).
- VirtIO vs. SATA/e1000 bei Windows: pragmatisch entscheiden.
- Realistische Dauer 4–6 h, überwiegend Wartezeit (16 GB Image-Pulls, zwei
  Windows-Installationen, AD-Promotion mit Reboots).