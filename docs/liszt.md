# liszt — VastAI GPU box

Run the AI pipeline on a rented [VastAI](https://vast.ai) GPU without redoing the
SSH-key → clone → `.env` → run dance every time, and without chasing a new IP/port
on each instance. `liszt` is not a NixOS host like `bach`/`satie` — it's a container
image we build and run on ephemeral rented GPUs.

**How it works.** A declarative CUDA + Tailscale container image
([`modules/machines/liszt.nix`](../modules/machines/liszt.nix), built by
[nix2gpu](https://github.com/fleek-sh/nix2gpu)) is pushed to GHCR by CI and used as
a VastAI template. On boot the container joins the tailnet as **`liszt`**, so
`ssh root@liszt` always works via MagicDNS + Tailscale SSH — whatever ephemeral
address VastAI hands out. You land in a box that already has CUDA, git, python and
`uv`; you just clone the repo, drop `.env`, and run.

```
modules/machines/liszt.nix ─CI (x86_64 runner)─▶ ghcr.io/demic-dev/liszt:latest
                                                        │
                              VastAI template (Entrypoint mode, TS_AUTHKEY env)
                                                        │
                     instance boots ▶ tailscaled (userspace) up --hostname=liszt --ssh
                                                        │
                                  ssh root@liszt   (stable, via MagicDNS)
```

> **Why containers, not NixOS.** VastAI instances are Docker containers, not VMs —
> there's no bootloader/disk to `nixos-anywhere`/`nixos-infect`. The reproducible
> *image* + Tailscale gives the same benefit (stable name, pinned environment)
> without needing NixOS on the box.

---

## One-time setup

### 1. GitHub: PAT for pushing the image

CI pushes to GHCR with nix2gpu's `copyToGithub`, which needs a real user token.

- Create a **classic Personal Access Token** with the **`write:packages`** scope.
- Add it as an **Actions repository secret** named **`GHCR_TOKEN`**.
- After the first successful push, make the `liszt` package **public** (or configure
  VastAI to pull with credentials) at
  `https://github.com/users/demic-dev/packages/container/liszt/settings`.

(The default `GITHUB_TOKEN` won't work: nix2gpu's push script calls `gh api user`,
which the Actions bot token can't.)

### 2. Tailscale: auth key + SSH ACL

In the [Tailscale admin console](https://login.tailscale.com/admin):

- **Auth key** (Settings → Keys → *Generate auth key*): make it **Reusable**,
  **Ephemeral**, and **Pre-approved**; tag it **`tag:vastai`**. Copy the key
  (`tskey-auth-…`) — it goes in the VastAI template env (step 3). Ephemeral means
  the node auto-removes itself shortly after you destroy the instance, so the `liszt`
  name never accumulates `liszt-1`, `liszt-2` suffixes.
- **MagicDNS**: ensure it's enabled (DNS tab) — it is already, for the existing tailnet.
- **ACL** (Access Controls): allow yourself to Tailscale-SSH into the tagged node as
  root, and define the tag owner:

  ```jsonc
  "tagOwners": {
    "tag:vastai": ["autogroup:admin"]
  },
  "ssh": [
    {
      "action": "accept",
      "src":    ["autogroup:member"],
      "dst":    ["tag:vastai"],
      "users":  ["root"]
    }
  ]
  ```

### 3. VastAI: the template

Create one template (Templates → *New*) and reuse it forever:

- **Image:** `ghcr.io/demic-dev/liszt:latest`
- **Launch mode: Entrypoint.** *Not* SSH/Jupyter — those replace the image's
  entrypoint and break the Nix init. (VastAI's own docs say to fall back to
  Entrypoint on "obscure loading errors" with custom images.)
- **Environment variables:**
  - `TAILSCALE_AUTHKEY` = the `tskey-auth-…` key from step 2. *(This is the only
    secret; it lives in the template, never in the image.)*
  - *(optional)* `TAILSCALE_HOSTNAME` = `liszt` — the default is already `liszt`; set
    this only if you want to run two boxes at once under different names.
- **On-start Script:** leave it **empty**. Everything is env-driven — the image's
  supervised services inherit the template env vars, so `tailscaled` comes up and
  `tailscale up --hostname=liszt --ssh` runs on its own. (No onstart is needed, and
  onstart doesn't reliably run under Entrypoint launch mode anyway.)

That's it. The image bakes your `michele` public keys into `root`'s
`authorized_keys` as a fallback, and Tailscale SSH handles the normal path.

---

## Building / updating the image

You **cannot build locally** — CUDA is x86_64-only and every machine here is aarch64.

- **Normal path:** push to `main` touching `modules/machines/**` (or run the workflow
  manually): **Actions → "Build & push liszt (VastAI GPU image)" → Run workflow**. It
  builds on an x86_64 runner and pushes `:latest` to GHCR.
- **Local sanity check (eval only, no build):**
  ```bash
  nix eval --accept-flake-config .#packages.x86_64-linux.liszt.drvPath
  ```
  This resolves the whole module; it stops at an x86_64 import-from-derivation,
  which is expected on aarch64 and not an error in the config.
- **Alternative to CI:** register an x86_64 remote builder and
  `nix run --accept-flake-config .#packages.x86_64-linux.liszt.copyToGithub` (needs
  `gh` logged in with `write:packages`).

To change what's in the box — extra tools, pinned CUDA version, a baked model —
edit `modules/machines/liszt.nix` (`systemPackages`, `cuda.packages`, `extraEnv`, …).

---

## Per-session usage

1. **Rent** an instance from the saved template, picking whatever GPU you need.
2. Wait for it to reach **"Running"** (~1 min), then:
   ```bash
   ssh root@liszt
   ```
3. Inside:
   ```bash
   git clone git@github.com:demic-dev/<pipeline-repo>.git
   cd <pipeline-repo>
   cp /path/to/.env .env          # or scp it: scp .env root@liszt:~/<pipeline-repo>/
   nvidia-smi                     # sanity: GPU is visible
   uv run <pipeline>              # torch etc. against the baked CUDA
   ```
4. **Destroy** the instance in the VastAI UI. The ephemeral tailnet node disappears
   on its own; next time, `liszt` is free again.

### Troubleshooting

- **`ssh root@liszt` doesn't resolve** → the node isn't up yet, or `TAILSCALE_AUTHKEY`
  is wrong/expired. Check the instance logs in VastAI for the `tailscale up` line;
  check the device list in the Tailscale console. On your laptop, `tailscale status`
  should list `liszt`.
- **`torch.cuda.is_available()` is `False`** → the nix2gpu startup patches driver
  libraries injected by VastAI's runtime; give it a few seconds after boot, and
  confirm `nvidia-smi` works first. If `nvidia-smi` fails, the host/driver side is
  the problem, not the image.
- **A benign warning** about a tailscale authkey *path* not existing is expected —
  we inject the key by env var, not by file.
