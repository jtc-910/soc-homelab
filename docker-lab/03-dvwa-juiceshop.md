# DVWA and Juice Shop: deliberately vulnerable Docker targets

Two intentionally vulnerable web apps, stood up fresh in Docker on `docker01` — not migrated from
anywhere, there was no prior instance. These exist for two things planned later in the roadmap: a
WAF project (nginx + ModSecurity/OWASP CRS, or pfSense as a WAF layer, Phase 3) and giving Wazuh
something realistic to detect attacks against, instead of only ever attacking the "real" lab
machines (DC01, WS01).

## Isolated from the rest of the lab

Both run in their own Docker Compose project, on their own bridge network (`vuln-net`), completely
separate from the Wazuh stack's network (`single-node_default`). They can't reach the Wazuh
containers directly — only the specific host ports I exposed (`8080` for DVWA, `3000` for Juice
Shop) are reachable at all, and only from the lab network, same as everything else here.

```yaml
services:
  dvwa:
    image: vulnerables/web-dvwa
    container_name: dvwa
    restart: unless-stopped
    profiles:
      - pentest
    ports:
      - "8080:80"
    # The image start script skips Apache if a stale apache2.pid survived in the
    # container layer (restart != recreate). tmpfs = always empty on start.
    tmpfs:
      - /var/run/apache2
    networks:
      - vuln-net

  juice-shop:
    image: bkimminich/juice-shop
    container_name: juice-shop
    restart: unless-stopped
    profiles:
      - pentest
    ports:
      - "3000:3000"
    networks:
      - vuln-net

networks:
  vuln-net:
    driver: bridge
```

```bash
docker compose --profile pentest up -d
```

## Not running by default

Both containers sit behind the `pentest` [Compose profile](https://docs.docker.com/compose/how-tos/profiles/).
A plain `docker compose up -d` in this project directory ignores them entirely, so bringing the
rest of the lab up never creates them by accident — most days I don't need attack targets running,
just the Wazuh stack. Once they *have* been created via the profile, though, they do come back after
a host reboot (see the `restart` note below) until I explicitly `down` them. To use them:

```bash
docker compose --profile pentest up -d      # start
docker compose --profile pentest down       # stop and remove
```

`restart: unless-stopped` is still useful *within* a pentest session — if the VM reboots while I'm
mid-exercise, they come back up rather than needing a manual restart — but it only takes effect once
a container has actually been created via the profile; it doesn't override the profile filter itself.

## DVWA "Up" but not answering: a stale Apache PID file (found 2026-10-10)

During the post-migration audit, `docker ps` showed `dvwa` as `Up`, but `curl` on port 8080 got
`Connection reset by peer`. Inside the container only MariaDB and the image's `tail -f` were
running — no Apache at all, and Apache's error log had no entry for that day.

The cause is in the image's `/main.sh`: it starts Apache via `service apache2 start`, and Debian's
init script refuses to start if `/var/run/apache2/apache2.pid` exists and its PID belongs to a
running process. That file sat in the container's writable layer from a run weeks earlier
(`docker restart` and a host reboot reuse the same container, they don't recreate it), and PIDs
inside a container are low and repeat between boots — so the stale PID pointed at some other live
process, and the script decided Apache was already running. The `tail -f` keeps PID 1 alive, so
Docker reports the container healthy the whole time.

Fix: mount `/var/run/apache2` as `tmpfs` (see the Compose file above), so the PID file can never
survive a restart. Verified with several `docker restart dvwa` cycles in a row, each answering
`200` on `/login.php`. The broader lesson: `Up` only means PID 1 is alive. For a service check,
test the actual port (the lab health check in [`automation/`](../automation/) does exactly that).

## DVWA needed x86 emulation [ARM/UTM, historical]

> This whole section is a snapshot of a problem that no longer exists: `docker01` is now Ubuntu
> x86_64 on Proxmox VE, so DVWA's amd64-only image runs natively with no emulation layer needed at
> all. Kept for the record — see
> [05-hardware-migration.md](05-hardware-migration.md).

Juice Shop started cleanly — its image is multi-arch and runs natively on ARM64. DVWA didn't:

```
exec /main.sh: exec format error
```

The `vulnerables/web-dvwa` image only ships an `amd64` build, and this VM is ARM64 (Apple Silicon,
same as every other machine in this lab). "exec format error" is the telltale sign the host has no
emulation layer registered at all for foreign-architecture binaries — Docker doesn't emulate
anything on its own, it needs `binfmt_misc` handlers pointing at an emulator like QEMU.

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
docker compose up -d --force-recreate dvwa
```

That registers the QEMU user-mode emulators system-wide, and DVWA started cleanly afterward — slower
than a native container would be, but perfectly usable for a lab.

![DVWA login page, reachable at http://192.168.100.30:8080](../assets/screenshots/docker-lab-03-dvwa-login.png)

![Juice Shop home page, reachable at http://192.168.100.30:3000](../assets/screenshots/docker-lab-03-juiceshop-home.png)

## Why this matters for SOC work

Having deliberately vulnerable, disposable targets in the same lab as the SIEM means I can generate
realistic attack traffic — SQL injection, XSS, broken auth — on demand and watch how (or whether) it
shows up in detection, without touching the actual domain-joined machines. It's also a preview of a
recurring theme in real infrastructure: knowing when to reach for architecture emulation instead of
assuming every container image just works everywhere, which matters a lot on ARM hardware
specifically.
