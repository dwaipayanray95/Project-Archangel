# Project Archangel

Personal Oracle Cloud (OCI) Always-Free VPS — vibecoding box, dev sandbox, and home for whatever self-hosted experiments come next.

This repo is the **recovery runbook**. If the server dies, gets deleted, or a fresh account is needed, everything required to rebuild it from scratch lives here.

---

## 1. Account & Region

- **Cloud provider:** Oracle Cloud Infrastructure (OCI), Always Free tier
- **Region:** `ap-mumbai-1` (Mumbai) — only one availability domain (`AD-1`), so no AD-switching workaround for capacity issues
- **Free tier limits on this account:** capped at **2 OCPU / 12 GB** total for Ampere A1 (Arm) shapes — lower than the commonly-advertised 4 OCPU/24GB, likely account/region dependent
- Also available separately: 2x AMD-based "Micro" instances (1/8 OCPU, 1GB RAM each) — not yet used

## 2. Instance Configuration

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

## 3. SSH Access

- Keypair was generated via the OCI Console during instance creation ("Generate a key pair for me")
- **Private key** lives at: `~/Downloads/project-archangel.key` on Ray's Mac — **never commit this to git, never copy it onto the VPS itself**
- **Public key** lives at: `~/Downloads/project-archangel-public.key.pub` — safe to share/commit, this is what's actually installed in the VPS's `authorized_keys`
- If the private key is ever lost: don't try to recover it — generate a fresh keypair and update `authorized_keys` on next rebuild. A password manager (Bitwarden/1Password secure file storage) is the recommended backup location for the private key — **not** GitHub, not the VPS itself.

Connect with:
```bash
ssh -i ~/Downloads/project-archangel.key ubuntu@<VPS_PUBLIC_IP>
```

## 4. OCI CLI Setup (on the machine used to provision/manage the VPS)

1. Install OCI CLI (official install script) — installed to `~/bin/oci` on Mac, added to PATH via `~/.zshrc`
2. Run `oci setup config`:
   - Region: `ap-mumbai-1`
   - Generates a separate RSA **API signing keypair** (different from the SSH keypair above) at `~/.oci/oci_api_key.pem` (private) and `~/.oci/oci_api_key_public.pem` (public)
   - No passphrase set
3. Upload the API public key in OCI Console → **My Profile → API Keys**
4. Verify with: `oci iam region list`

**Key OCIDs (this account/tenancy):**
- Tenancy/Compartment OCID: `ocid1.tenancy.oc1..aaaaaaaabarxx7mbciow4ma43m4gl5q6pcbenxa3xynmq7eztbr3sgnfhfia`
- Availability Domain: `EBDD:AP-MUMBAI-1-AD-1`
- Subnet OCID: `ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaayuhquek4rhpeu6hyv4gwmvfbiwyetlqtrdkrjeg2z3soauq5i2fq`

> ⚠️ OCIDs are account-specific. If rebuilding under a **different** OCI account/tenancy, all of the above OCIDs must be re-fetched — they will not match.

## 5. The Capacity Problem

Oracle's free-tier Ampere A1 capacity is notoriously scarce, especially in Indian regions. Instance creation via the Console repeatedly failed with:
```
Out of capacity for shape VM.Standard.A1.Flex in availability domain AD-1
```
This is a widely-documented issue — community reports mention it can take anywhere from days to 1–3 months of continuous retrying to catch a free slot, sometimes 100,000+ attempts.

**Solution:** an auto-retry script (see `scripts/oci_retry.sh`) that loops the launch command until it succeeds.

## 6. Retry Script

See [`scripts/oci_retry.sh`](scripts/oci_retry.sh).

- Retries every **120 seconds** (tuned — 60s triggered rate-limiting; 120s is a healthy interval per community consensus, range is typically 60s–5min)
- On `TooManyRequests`, backs off for an additional 120s
- On success: prints the created instance JSON and plays a sound (macOS `afplay`)
- Uses `--ssh-authorized-keys-file` pointing at the public key (not raw JSON metadata — avoids key-escaping issues)

Run it with:
```bash
chmod +x scripts/oci_retry.sh
./scripts/oci_retry.sh
```
Needs to keep running (Mac must not sleep) until it succeeds — see Section 7 for a way to avoid babysitting a laptop.

## 7. Alternative: GitHub Actions

To avoid keeping a Mac awake indefinitely, the retry logic runs on a schedule via GitHub Actions instead: [`.github/workflows/oci-retry.yml`](.github/workflows/oci-retry.yml), calling [`scripts/oci_retry_once.sh`](scripts/oci_retry_once.sh) (a single-attempt variant of `oci_retry.sh` — each workflow run is one attempt, the cron schedule provides the loop).

- Free tier: 2,000 minutes/month for private repos — a 5-minute-interval scheduled job that runs ~10–20s per invocation uses roughly 100–150 min/month, well within budget
- GitHub's minimum reliable schedule interval is ~5 minutes (not the tighter 120s used locally)
- This is a legitimate, lightweight use of Actions — not the kind of heavy/abusive automation prohibited in GitHub's terms (e.g. crypto mining)
- Idempotent: the script checks for a `RUNNING` instance named `project-archangel` first and exits early if one already exists, so it's safe to leave the schedule running
- "Out of capacity" / rate-limited responses exit `0` (not a failure) so they don't spam failure-notification emails every 5 minutes; only a genuinely unexpected error exits non-zero

**Required GitHub encrypted secrets** (Settings → Secrets and variables → Actions), all specific to *this* OCI account/tenancy:

| Secret | Value |
|---|---|
| `OCI_USER_OCID` | Your OCI user OCID (`oci iam user list`, or Console → My Profile) |
| `OCI_FINGERPRINT` | Fingerprint of the API signing key uploaded in Console → My Profile → API Keys |
| `OCI_TENANCY_OCID` | Tenancy OCID (see section 4) |
| `OCI_REGION` | `ap-mumbai-1` |
| `OCI_API_PRIVATE_KEY` | Full contents of `~/.oci/oci_api_key.pem` (the API signing key, **not** the SSH key) |
| `OCI_SSH_PUBLIC_KEY` | Full contents of `~/Downloads/project-archangel-public.key.pub` |

Never commit any of these as plain files — secrets only. Once the instance launches successfully, disable or delete the workflow (Actions tab → OCI Instance Retry → "..." → Disable workflow) so it stops running.

## 8. Post-Launch TODO (once the instance exists)

- [ ] Retrieve public IP from instance JSON / OCI Console
- [ ] First SSH connection, confirm access
- [ ] Open any additional firewall/security-list ports beyond SSH (22) as needed per service
- [ ] Install dev tooling (Claude Code, git, etc.)
- [ ] Consider a lightweight server dashboard (e.g. Cockpit) for visual monitoring — full desktop environments (GNOME/KDE) are **not** recommended, too heavy for a 1 OCPU/6GB box
- [ ] Set up `tmux`/`screen` for persistent sessions that survive SSH disconnects

## 9. Related / Future Projects

- **Archangel control app** — a personal hobby app (Android-first) to remotely control/interact with this VPS. Two directions under consideration: installing an existing lightweight UI (Cockpit/Portainer) vs. building a custom API + app. Wants an in-app terminal (SSH-backed) for running things like Claude Code remotely. Private key handling: import once, store in Android Keystore/iOS Keychain — never bundled into the app package itself.
- Possible future use cases for the VPS itself: self-hosted WireGuard VPN, backend/staging host for the Us Together and Outstand app projects, personal automation projects (finance tracking, uptime monitoring, morning dashboard, etc.)

---
*Last updated: 2026-08-27*
