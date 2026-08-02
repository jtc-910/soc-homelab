# Hardening the Wazuh Ubuntu VM — SSH and Fail2ban

The Wazuh VM had been running with password-based SSH login since I first set it up. This step
locks that down: key-based login only, and Fail2ban to catch brute-force attempts against whatever
is still exposed. UFW rules, turning off unnecessary services, and automatic security updates are
the remaining part of Phase 1.7 and follow in a later update to this page.

## Why this matters

SSH is the most common way into any internet-facing Linux box. Password logins can be brute-forced;
a stolen or guessed password is often all an attacker needs. Key-based login removes that entire
attack path — without the private key, password guessing doesn't get you anywhere. Fail2ban adds a
second layer on top: it watches the auth log and temporarily bans IPs that fail to log in
repeatedly, which slows down or stops automated brute-force tools even against services that still
allow some form of password prompt (or against other daemons later on).

## Setting up key-based login

On my Mac (not on the VM itself):

```bash
ssh-keygen -t ed25519 -C "wazuh-lab"
ssh-copy-id wazuh@192.168.100.30
```

`ssh-copy-id` connects once with my existing (password) credentials and appends the new public key
to `~/.ssh/authorized_keys` on the VM. After that, `ssh wazuh@192.168.100.30` logs in with the key,
no password prompt.

## Turning off password login

With the key working, password authentication becomes unnecessary — and a live weak point if left
enabled, so I disabled it in `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PermitRootLogin no
```

`PermitRootLogin no` closes off the more damaging half of the same problem: even if something did
guess a password, it couldn't be root's.

![PasswordAuthentication no and PermitRootLogin no set in sshd_config](../assets/screenshots/linux-lab-01-sshd-config.png)

### The catch: `sshd_config.d` overrides the main file

Restarting `sshd` and testing didn't work at first — password login still succeeded. The reason:
Ubuntu's default `sshd_config` includes everything in `/etc/ssh/sshd_config.d/*.conf` at the very
top of the file, and `sshd` uses the *first* value it finds for a given setting. A cloud-init
generated file in that folder, `50-cloud-init.conf`, had its own `PasswordAuthentication yes`,
which was being read before my change in the main file — so it won.

```bash
sudo nano /etc/ssh/sshd_config.d/50-cloud-init.conf
```

Changed `yes` to `no` there instead, and restarted `sshd` again.

![PasswordAuthentication changed to no inside the cloud-init override file](../assets/screenshots/linux-lab-01-cloud-init-config-change.png)

```bash
sudo systemctl restart sshd
```

## Verifying it

Before closing the working SSH session, I opened a new terminal window and tested there first —
important, since a mistake in `sshd_config` can otherwise lock you out with no way back in except
the UTM console.

Key login, no password prompt:

![Successful SSH login using the key, no password prompt](../assets/screenshots/linux-lab-01-key-login-working.png)

Forcing a password-only attempt now gets refused outright instead of prompting:

```bash
ssh -o PubkeyAuthentication=no wazuh@192.168.100.30
```

![Password-only login attempt refused](../assets/screenshots/linux-lab-01-password-login-denied.png)

## Fail2ban

```bash
sudo apt install fail2ban
sudo systemctl enable --now fail2ban
```

Fail2ban ships with a default SSH jail, but I put my own settings in `jail.local` rather than
editing the packaged `jail.conf` directly, since that file gets overwritten on updates:

```bash
sudo nano /etc/fail2ban/jail.local
```

```
[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 3600
findtime = 600
```

Three failed attempts within 10 minutes bans the source IP for an hour.

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

![fail2ban-client status sshd showing the sshd jail active](../assets/screenshots/linux-lab-01-fail2ban-status.png)

### Testing the ban

Since password login is already disabled, I couldn't trigger the ban with wrong passwords. Fail2ban
also picks up "invalid user" attempts though, so a few connections with made-up usernames did the
job just as well:

```bash
ssh fakeuser1@192.168.100.30
ssh fakeuser2@192.168.100.30
ssh fakeuser3@192.168.100.30
ssh fakeuser4@192.168.100.30
```

After a few of these, my own Mac's IP showed up as banned:

![fail2ban-client status sshd showing my IP address banned](../assets/screenshots/linux-lab-01-fail2ban-banned.png)

And at that point new SSH connections from that IP were refused outright — including my own, which
also knocked me out of my still-open session:

![Connection refused after the IP was banned](../assets/screenshots/linux-lab-01-fail2ban-connection-refused.png)

That's expected behavior, but it meant getting back in had to go through the UTM console directly
(not SSH), logging in locally on the VM, and removing the ban:

```bash
sudo fail2ban-client set sshd unbanip <my-mac-ip>
```

![My IP address removed from the ban list](../assets/screenshots/linux-lab-01-fail2ban-unbanned.png)

## What's still open for 1.7

- Basic UFW firewall rules
- Turning off unnecessary services
- Automatic security updates

These will be added to this same page once done.

## Why this matters for SOC work

This is the same logic behind most real hardening baselines: remove the weakest authentication
method entirely rather than trying to make it stronger, and add a second control (Fail2ban) that
still works even if the first one is somehow bypassed later. Locking myself out with the Fail2ban
test was also a useful (if unplanned) lesson — it's exactly the kind of self-inflicted lockout that
makes out-of-band access (a console, IPMI, cloud provider's serial console) worth having before you
harden anything remotely.
