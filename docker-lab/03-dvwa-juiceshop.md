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
    ports:
      - "8080:80"
    networks:
      - vuln-net

  juice-shop:
    image: bkimminich/juice-shop
    container_name: juice-shop
    restart: unless-stopped
    ports:
      - "3000:3000"
    networks:
      - vuln-net

networks:
  vuln-net:
    driver: bridge
```

```bash
docker compose up -d
```

## DVWA needed x86 emulation

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
