# docker01 network fixes (not obvious from cloud-init alone)

Two fixes live on the running `docker01` VM that aren't self-explanatory from
`cloud-init-docker01.yaml` on their own — write them down here so a rebuild doesn't lose
them and so the "why" survives past the person who found it.

## 1. virtio-net TX checksum offload corrupts UDP behind the NAT bridge

**Symptom:** `apt update`/`apt upgrade` and `docker pull` fail intermittently and
unpredictably on `vmbr1` (the isolated, NAT'd lab network) — not a hard failure, just
enough packet loss on UDP (DNS in particular) to make provisioning flaky.

**Cause:** virtio-net's TX checksum offload hands the checksum job to the (virtual) NIC,
which doesn't compute it correctly for UDP packets crossing Proxmox's NAT/masquerade path
on `vmbr1`. The kernel trusts the (wrong) checksum and the packet gets silently dropped
downstream.

**Fix:** disable TX checksum offload on the guest's NIC, persistently (a plain `ethtool -K`
call doesn't survive a reboot):

```ini
# /etc/systemd/system/disable-eth0-tx-offload.service
[Unit]
Description=Disable virtio-net tx checksum offload (works around UDP corruption behind Proxmox NAT bridge)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K eth0 tx off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

`systemctl enable --now disable-eth0-tx-offload.service`. This is now baked into
`cloud-init-docker01.yaml` via `write_files` + `runcmd`, so a fresh `docker01` gets it on
first boot without a manual step.

**If this resurfaces on a future Linux VM on `vmbr1`:** suspect the same virtio-checksum
issue first, don't re-debug from scratch.

## 2. systemd-resolved's stub listener hangs independently

Even with the fix above, `systemd-resolved`'s local stub (`127.0.0.53:53`) intermittently
stopped answering. Unrelated root cause, same symptom class (DNS flakiness), so it's easy
to mistake one fix for having solved both.

**Fix:** point resolution straight at public resolvers and disable the stub listener:

```ini
# /etc/systemd/resolved.conf.d/99-static-dns.conf
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSStubListener=no
```

`/etc/resolv.conf` then points directly at `1.1.1.1`/`1.0.0.1` instead of the stub. Also
baked into `cloud-init-docker01.yaml` now.

## The interface is `eth0`, not `ens18`

Confirmed on the running VM (`ip -br addr`): the virtio-net NIC comes up as `eth0`, not
the predictable-interface-name `ens18` Ubuntu 24.04 typically assigns on real/PCI
hardware. Both fixes above target `eth0` for that reason. If this VM is ever rebuilt on
different virtual hardware (e.g. a different NIC model or bus), re-verify the interface
name before assuming these units still apply unchanged.
