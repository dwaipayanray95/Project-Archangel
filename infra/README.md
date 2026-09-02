# Project Archangel — Infra

Personal Oracle Cloud (OCI) Always-Free VPS setup — vibecoding box, dev sandbox, and home for whatever self-hosted experiments come next.

This is the **recovery runbook**. If a server dies, gets deleted, or a fresh account is needed, everything required to rebuild it from scratch lives here.

---

## 1. Account & Region

- **Cloud provider:** Oracle Cloud Infrastructure (OCI), Always Free tier
- **Region:** `ap-mumbai-1` (Mumbai) — only one availability domain (`AD-1`), so no AD-switching workaround for capacity issues
- **Free tier limits on this account:** capped at **2 OCPU / 12 GB** total for Ampere A1 (Arm) shapes — lower than the commonly-advertised 4 OCPU/24GB, likely account/region dependent
- Also available separately: up to 2x AMD-based "Micro" instances (1/8 OCPU, 1GB RAM each) — one is in use, see section 3

## 2. Ampere A1 Instance Configuration

| Setting | Value |
|---|---|
| Shape | `VM.Standard.A1.Flex` (Ampere ARM, Always Free eligible) |
| OCPUs | 1 |
| Memory | 6 GB |
| OS Image | Canonical Ubuntu 24.04 (plain, not Minimal), ARM build |
| Image OCID used | `ocid1.image.oc1.ap-mumbai-1.aaaaaaaamtc6jgk5qnf36vkudldlyn3fhmngilbepfgxdir3v3hlujs2gcbq` (2026.07.17-0 — **check for newer image OCIDs when rebuilding**, these expire/rotate) |
| VCN/Subnet | `vcn-20260506-1516` / `subnet-20260506-1516` (auto-selected defaults) |
| Public IPv4 | Assigned automatically |
| IPv6 | Off |
| Shielding / Confidential Computing | Off (not needed for this use case) |
| Boot volume | Default ~46.6GB, in-transit encryption on, Oracle-managed keys |

**Why 1 OCPU/6GB instead of the full 2/12?** Smaller requests succeed more often when scavenging for scarce free-tier Ampere capacity — this is a widely recommended trick, not just our guess. Once the box is up, it can be resized later if more capacity frees up.

**Status:** not yet allocated — the retry automation in section 8 is actively chasing this.

## 3. AMD Micro Instance Configuration (`Archangel-Mk1`)

Provisioned directly via the OCI Console — no capacity scarcity issue for this shape, so no retry script needed.

| Setting | Value |
|---|---|
| Instance name | `Archangel-Mk1` |
| Shape | `VM.Standard.E2.1.Micro` (AMD, Always Free eligible) |
| OCPUs | 1/8 |
| Memory | 1 GB |
| OS Image | Canonical Ubuntu 24.04 (plain, not Minimal), x86_64 build — exact image OCID not captured at launch time (selected via Console default); **grab the current x86_64 Ubuntu 24.04 image OCID from the Console if rebuilding** |
| Public IPv4 | `161.118.191.143` |
| Created | 2026-09-01 |

**Status:** running, baseline setup complete (see section 9), WireGuard configured with 3 peers (see section 10) — OCI Security List rule for `51820/udp` still needs adding before any device can actually connect.

## 4. SSH Access

- Keypair was generated via the OCI Console during instance creation ("Generate a key pair for me")
- **Private key** lives at: `~/Downloads/project-archangel.key` on Ray's Mac — **never commit this to git, never copy it onto the VPS itself**
- **Public key** lives at: `~/Downloads/project-archangel-public.key.pub` — safe to share/commit, this is what's actually installed in the VPS's `authorized_keys`
- **Same keypair is reused across both instances** (Ampere and AMD Micro) — simpler to manage, at the cost of both boxes sharing blast radius if the private key is ever compromised. Acceptable tradeoff for a personal sandbox setup.
- If the private key is ever lost: don't try to recover it — generate a fresh keypair and update `authorized_keys` on next rebuild. A password manager (Bitwarden/1Password secure file storage) is the recommended backup location for the private key — **not** GitHub, not the VPS itself.
- **Local file permissions matter:** SSH refuses to use a private key file that's readable by other users. If you see `Permissions 0644 for '...' are too open` / `bad permissions`, fix with:
  ```bash
  chmod 600 ~/Downloads/project-archangel.key
  ```

Connect with:
```bash
ssh -i ~/Downloads/project-archangel.key ubuntu@<VPS_PUBLIC_IP>
```
First connection to a given IP will prompt to confirm the host key fingerprint — type `yes`. This is expected and only happens once per IP (seeing it again later on the same IP is a signal the server was rebuilt).

## 5. OCI CLI Setup (on the machine used to provision/manage the VPS)

1. Install OCI CLI (official install script) — installed to `~/bin/oci` on Mac, added to PATH via `~/.zshrc`
2. Run `oci setup config`:
   - Region: `ap-mumbai-1`
   - Generates a separate RSA **API signing keypair** (different from the SSH keypair above) at `~/.oci/oci_api_key.pem` (private) and `~/.oci/oci_api_key_public.pem` (public)
   - **This key *is* passphrase-encrypted** (despite earlier notes here once saying otherwise) — confirmed when the GitHub Actions workflow in section 8 tried to load it non-interactively. The passphrase itself lives wherever the Mac's `oci setup config` prompt answer went (password manager recommended, same as the SSH key) — it also has to be supplied as the `OCI_API_KEY_PASSPHRASE` GitHub secret for section 8's automation to authenticate
3. Upload the API public key in OCI Console → **My Profile → API Keys**
4. Verify with: `oci iam region list`

**Key OCIDs (this account/tenancy):**
- Tenancy/Compartment OCID: `ocid1.tenancy.oc1..aaaaaaaabarxx7mbciow4ma43m4gl5q6pcbenxa3xynmq7eztbr3sgnfhfia`
- Availability Domain: `EBDD:AP-MUMBAI-1-AD-1`
- Subnet OCID: `ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaayuhquek4rhpeu6hyv4gwmvfbiwyetlqtrdkrjeg2z3soauq5i2fq`

> ⚠️ OCIDs are account-specific. If rebuilding under a **different** OCI account/tenancy, all of the above OCIDs must be re-fetched — they will not match.

## 6. The Capacity Problem (Ampere A1 only)

Oracle's free-tier Ampere A1 capacity is notoriously scarce, especially in Indian regions. Instance creation via the Console repeatedly failed with:
```
Out of capacity for shape VM.Standard.A1.Flex in availability domain AD-1
```
This is a widely-documented issue — community reports mention it can take anywhere from days to 1–3 months of continuous retrying to catch a free slot, sometimes 100,000+ attempts. **The AMD Micro shape has no such scarcity problem** — that instance was created directly via the Console with no retrying needed.

**Solution:** an auto-retry script (see `scripts/oci_retry.sh`) that loops the launch command until it succeeds.

## 7. Retry Script

See [`scripts/oci_retry.sh`](scripts/oci_retry.sh).

- Retries every **120 seconds** (tuned — 60s triggered rate-limiting; 120s is a healthy interval per community consensus, range is typically 60s–5min)
- On `TooManyRequests`, backs off for an additional 120s
- On success: prints the created instance JSON and plays a sound (macOS `afplay`)
- Uses `--ssh-authorized-keys-file` pointing at the public key (not raw JSON metadata — avoids key-escaping issues)

Run it with (from the repo root):
```bash
chmod +x infra/scripts/oci_retry.sh
./infra/scripts/oci_retry.sh
```
Needs to keep running (Mac must not sleep) until it succeeds — see Section 8 for a way to avoid babysitting a laptop.

## 8. Alternative: GitHub Actions

To avoid keeping a Mac awake indefinitely, the retry logic runs on a schedule via GitHub Actions instead: [`.github/workflows/oci-retry.yml`](../.github/workflows/oci-retry.yml), calling [`scripts/oci_retry_once.sh`](scripts/oci_retry_once.sh) (a single-attempt variant of `oci_retry.sh` — each workflow run is one attempt, the cron schedule provides the loop).

- Free tier: 2,000 minutes/month for private repos. Configured for every **15 minutes** (not 5 — a 5-minute interval, worst case run continuously for a full month, would use ~6,500 min/month and blow the budget; 15 minutes with pip caching keeps worst-case usage to roughly 700-900 min/month)
- **In practice, GitHub's `schedule:` trigger is best-effort and gets delayed significantly** — observed real gaps between scheduled runs have ranged from minutes to over 16 hours, not a steady 15-minute cadence. This is a documented GitHub platform limitation, not a bug in this workflow. Trigger it manually (Actions tab → **OCI Instance Retry** → **Run workflow**) any time you want an immediate attempt instead of waiting
- This is a legitimate, lightweight use of Actions — not the kind of heavy/abusive automation prohibited in GitHub's terms (e.g. crypto mining)
- Idempotent: the script checks for an existing instance named `project-archangel` in any non-terminated state first and exits early if one is found, so it's safe to leave the schedule running
- "Out of capacity" / rate-limited responses exit non-zero-but-not-a-failure (`75`) so they don't spam failure-notification emails; only a genuinely unexpected error fails the job
- A dedicated "Verify OCI credentials" step runs `oci iam region list` before ever attempting a launch — if any secret is wrong (typo'd OCID, mismatched fingerprint/key pair, wrong passphrase, malformed key file), the job fails immediately at that step with a clear error, instead of the mistake surfacing later buried inside a launch failure. Check the failed run's logs (Actions tab → the red run → the relevant step) to see exactly what OCI rejected

**Required GitHub encrypted secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `OCI_USER_OCID` | Your OCI user OCID (`oci iam user list`, or Console → My Profile) |
| `OCI_FINGERPRINT` | Fingerprint of the API signing key uploaded in Console → My Profile → API Keys |
| `OCI_API_PRIVATE_KEY` | Full contents of `~/.oci/oci_api_key.pem` (the API signing key, **not** the SSH key) |
| `OCI_API_KEY_PASSPHRASE` | The API signing key's passphrase (see section 5 — it does have one) |
| `OCI_SSH_PUBLIC_KEY` | Full contents of `~/Downloads/project-archangel-public.key.pub` |

Tenancy OCID and region are *not* stored as secrets — they aren't sensitive (already public in section 5 above and hardcoded in the scripts), so they're hardcoded directly in the workflow file instead.

Never commit any of the above as plain files — secrets only. The workflow disables itself automatically once the instance launches successfully (see the last step in `oci-retry.yml`), so no manual cleanup is needed.

## 9. Baseline Post-Launch Setup (repeat for every new instance)

Applied to `Archangel-Mk1` (AMD Micro) on 2026-09-01. **Run this same sequence on the Ampere A1 instance once it's allocated.**

**Scripted** (does steps 3-7 below): [`infra/scripts/baseline_setup.sh`](scripts/baseline_setup.sh) — safe to re-run any time, every step checks whether it's already done first.
```bash
git clone https://github.com/dwaipayanray95/Project-Archangel.git && cd Project-Archangel
./infra/scripts/baseline_setup.sh
```

Manual steps (what the script above actually does, kept here as reference/fallback):

1. **Retrieve the public IP** — OCI Console → instance → Details tab → Public IP Address
2. **First SSH connection**, confirm access (accept the host key fingerprint prompt — see section 4)
3. **Update the base system:**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
4. **Add swap** — critical on low-RAM shapes (the AMD Micro's 1GB especially), prevents an OOM crash from a memory spike:
   ```bash
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```
   Verify with `free -h` — should show a `Swap:` line with `2.0Gi` total.
5. **Install tmux** — so long-running sessions/processes survive an SSH disconnect:
   ```bash
   sudo apt install -y tmux
   ```
   Start a session with `tmux new -s main`; reattach later with `tmux attach -t main`.
6. **Basic firewall** (`ufw` isn't preinstalled on this image — install it first):
   ```bash
   sudo apt install -y ufw
   sudo ufw allow OpenSSH
   sudo ufw enable
   ```
   Confirm with `y` when prompted about disrupting the current SSH session — allowing OpenSSH first prevents an actual lockout.
   > Note: this only configures the OS-level firewall. OCI also has its own network-level firewall (VCN Security List / Network Security Group) in front of it — opening a new port later (e.g. WireGuard's, or the app's API) will likely need **both** `ufw allow <port>` *and* a Security List rule in the OCI Console. See section 10 for a real instance of this gotcha.
7. **Verify everything held:**
   ```bash
   free -h && sudo ufw status
   ```

Not yet done on any instance (deferred until the `app/` backend exists): installing dev tooling like Claude Code/git, deploying the Go backend itself.

## 10. WireGuard VPN Setup

The Archangel API (`app/backend`) is designed to be reachable **only** over a WireGuard tunnel, never the public internet directly (see the backend's architecture plan — "the connection needs to be ultra secure"). This section sets up the WireGuard side of that; the Go binary itself isn't deployed yet.

**Scripted:** [`infra/scripts/wireguard_setup.sh`](scripts/wireguard_setup.sh)
```bash
./infra/scripts/wireguard_setup.sh
```
- Generates a server keypair and one peer keypair per device in the script's `PEERS` array (currently `phone`, `mac`, `windows` — edit the array to add/remove devices)
- Writes `/etc/wireguard/wg0.conf` (server) and one `.conf` per device, all `chmod 600`
- **Refuses to run if `/etc/wireguard/wg0.conf` already exists** — re-running it would regenerate every key and silently break every already-paired device. Pass `--force` if you genuinely want to regenerate everything (all devices then need to re-import their configs).
- Every generated key is verified non-empty (and, in testing, verified to actually round-trip correctly through `wg pubkey`) before being written into a config — see the incident notes below for why this check exists.
- Starts the tunnel (`wg-quick@wg0`) and opens `51820/udp` in `ufw`

Applied to `Archangel-Mk1` on 2026-09-02: server on `10.10.0.1/24`, three peers on `10.10.0.2` (phone), `10.10.0.3` (mac), `10.10.0.4` (windows).

**Pairing a device:**
- **Phone:** `sudo qrencode -t ansiutf8 < /etc/wireguard/phone.conf`, scan the printed QR with the official WireGuard app (**+** → **Scan from QR code**)
- **Mac / Windows:** the `.conf` files can't be scanned — they need to be transferred off the server (they contain a private key, so never paste their contents into chat/Slack/etc; use `scp` or a similar direct transfer), then imported into the WireGuard desktop app ("Import tunnel(s) from file...")

**Required OCI Console step (easy to miss):** `ufw` only controls the box's own OS-level firewall. OCI has a separate network-level firewall (VCN Security List) in front of that, and it does **not** automatically open just because `ufw` did. Add an ingress rule: instance → **Subnet** → **Security Lists** → default list → **Add Ingress Rule** — Source CIDR `0.0.0.0/0`, Protocol `UDP`, Destination Port `51820`. Without this, the tunnel will show as configured correctly on the server but no external device will ever be able to connect — traffic gets dropped before it reaches `ufw` at all.

**Incident notes (why the script is this defensive):** the first manual attempt at this setup hit two real, silent failures worth remembering:
1. `wg genkey | tee /etc/wireguard/x_private.key | wg pubkey | sudo tee ...` — only the second `tee` had `sudo`; the private key `tee` failed permission-denied and the key was lost, without the pipeline itself failing loudly (the public key still computed correctly since it was piped through in memory regardless of the failed write).
2. A `sudo` credential cache expired mid-setup (between separate commands run several minutes apart while working through this interactively), causing a later `$(sudo cat server_public.key)` inside a variable assignment to silently return empty — which then got written into multiple device config files as a blank `PublicKey =` line, with no error at any point.

Both are exactly the class of bug that "did it print an error?" doesn't catch — the script's `require_nonempty` checks throughout, and running everything as one continuous script (so there's no time gap for a sudo cache to expire mid-setup), exist specifically because of this.

## 11. Master Setup Script

[`infra/scripts/install-archangel.sh`](scripts/install-archangel.sh) is the canonical "how do I set this box up" entrypoint — a thin orchestrator that runs `baseline_setup.sh` then `wireguard_setup.sh` in order (skipping WireGuard if it's already configured, to protect existing pairings). For a genuinely fresh instance:

```bash
git clone https://github.com/dwaipayanray95/Project-Archangel.git && cd Project-Archangel
./infra/scripts/install-archangel.sh
```

It's meant to keep growing as new milestones land — deploying `app/backend`'s binary + systemd unit becomes a new step here once that deployment tooling exists and is verified, rather than being written speculatively ahead of time.

## 12. Related / Future Projects

- **Archangel control app** — decided: a **Go backend** (single static binary, SSH bridge + resource watchdog + file browser, holds real SSH credentials server-side) plus a **Flutter frontend** (Android-first, one Dart codebase with iOS/web reach later). The app authenticates to the Go API with its own token — it never touches the SSH key directly. Lives in `app/` at the repo root once work starts (see the root [`README.md`](../README.md)); not yet started.
- Possible future use cases for the VPS(es): self-hosted WireGuard VPN, backend/staging host for the Us Together and Outstand app projects, personal automation projects (finance tracking, uptime monitoring, morning dashboard, etc.)

---
*Last updated: 2026-09-01*
