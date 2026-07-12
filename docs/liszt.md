# liszt — ephemeral VastAI GPU host

`liszt` is not a real machine: it is a Docker image (`modules/machines/liszt.nix`) built by
GitHub Actions (`.github/workflows/liszt-image.yml`) and pushed to the **private** GHCR
package `ghcr.io/demic-dev/liszt`. A rented VastAI GPU instance runs it directly; on boot it
joins the tailnet as `liszt` using an **ephemeral** Tailscale authkey and serves **Tailscale
SSH**. The workflow is:

> rent → `ssh root@liszt` → work → destroy the instance

Because the authkey is ephemeral, the tailnet node removes itself shortly after the instance
dies, so the `liszt` name is free again for the next rental. Nothing secret is baked into the
image — the authkey is injected at runtime by the VastAI template.

Inside you get fish (bobthefish, same config as satie/bach), git, uv, python, tmux, htop,
ripgrep, curl on top of the official `nvidia/cuda` Ubuntu base, so `nvidia-smi`, driver
injection and manylinux wheels (torch, vLLM, …) all work.

## One-time setup

### 1. Tailscale admin console

1. In the ACL policy, define a tag and let yourself own it:

   ```jsonc
   "tagOwners": {
     "tag:gpu": ["autogroup:admin"],
   }
   ```

2. Allow yourself to SSH into tagged nodes as root (plain `accept`, not check mode —
   check mode would require a browser round-trip every session):

   ```jsonc
   "ssh": [
     { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:gpu"], "users": ["root"] },
   ]
   ```

3. Create an authkey (Settings → Keys → *Generate auth key*):
   **Reusable** ✓, **Ephemeral** ✓, **Pre-authorized** ✓, **Tags**: `tag:gpu`, expiry 90 days.
   This is the `TS_AUTHKEY` value below. Rotate it when it expires.

### 2. GitHub

- The image is pushed automatically by the `liszt image` workflow (push to `main` touching
  the relevant files, or *Run workflow* manually). After the **first** run, check
  <https://github.com/demic-dev?tab=packages> → `liszt` → settings: it should be **private**
  (default for user-owned packages) and linked to the repo.
- Create a **classic PAT** with only the `read:packages` scope. VastAI uses it to pull the
  private image.

### 3. VastAI template

Create a template with:

| Field | Value |
|---|---|
| Image path/tag | `ghcr.io/demic-dev/liszt:latest` |
| Docker repository server | `ghcr.io` + your GitHub username + the `read:packages` PAT |
| Launch mode | **Docker ENTRYPOINT** (*not* SSH or Jupyter — those override the entrypoint and the tailscale bootstrap would never run) |
| Docker options | `-e TS_AUTHKEY=tskey-auth-…` |
| Disk | ≥ 40 GB (model weights) |
| Ports | none (tailscale is outbound-only) |

## Per-session workflow

1. Rent an instance from the template (filter on the GPU you need).
2. Watch the instance logs until `liszt joined the tailnet — ssh root@liszt` appears.
3. From satie: `ssh root@liszt`. You land in fish; auth is your tailnet identity, no keys.
4. If you will commit: `git config --global user.email <email>` (emails are agenix secrets
   on real hosts, so the image ships without one).
5. Python/GPU work — **always use uv-managed Python, never the nix `python3`**:

   ```sh
   uv python install 3.12
   uv venv ~/venv && source ~/venv/bin/activate.fish
   uv pip install vllm        # or torch, llama-cpp-python, …
   ```

   uv's interpreters use Ubuntu's dynamic loader, so wheels find the host-injected
   `libcuda.so.1`. The nix python's loader does not search Ubuntu's lib dirs.
6. Run long jobs inside `tmux`.
7. Destroy the instance when done. The tailnet node disappears on its own (ephemeral key);
   the name is reusable immediately-ish (see troubleshooting if not).

## Updating the image

- Any push to `main` touching `flake.{nix,lock}`, `env.nix`, `modules/machines/liszt.nix`,
  the fish/git home modules or the workflow rebuilds and pushes `:latest` (plus a
  commit-sha tag). VastAI pulls `:latest` on the next rental.
- **Re-pinning the CUDA base** (tag, digest and hash must change together in
  `modules/machines/liszt.nix`):

  ```sh
  nix run nixpkgs#nix-prefetch-docker -- --image-name nvidia/cuda \
    --image-tag 12.8.1-runtime-ubuntu24.04 --os linux --arch amd64
  ```

  Needs ~4 GB of temp space; if it fails locally, set the digest by hand
  (`skopeo inspect --format '{{.Digest}}' docker://nvidia/cuda:<tag>`), leave
  `hash = lib.fakeHash`, and copy the real hash from the first failing CI run
  ("hash mismatch … got: sha256-…"). That is also how the initial hash gets filled in.
- If you ever need `nvcc` in the image (compiling llama.cpp/flash-attn from source), switch
  the base tag from `-runtime-` to `-devel-` (~3× bigger). For occasional needs, prefer
  `uv pip install nvidia-cuda-nvcc-cu12` inside the venv instead.

## Troubleshooting

- **Node shows up as `liszt-1`** — the previous ephemeral node hasn't been reaped yet.
  Delete it in the admin console, or run `tailscale logout` on liszt before destroying the
  instance.
- **Container exits immediately** — `TS_AUTHKEY` unset or expired; the entrypoint fails
  loudly. Check the VastAI instance logs, and the key's expiry in the admin console.
- **`ssh root@liszt` refused** — check the SSH ACL rule (`tag:gpu`, user `root`) and
  `tailscale status` on satie. The node must be visible and tagged.
- **No GPU / `nvidia-smi` missing** — VastAI's nvidia runtime injection failed; check the
  template's GPU filters and the instance type.
- **Can't reach other tailnet hosts *from* liszt** — expected: tailscaled runs in userspace
  networking mode (no /dev/net/tun in VastAI containers), which handles inbound fine but
  not outbound into the tailnet. If ever needed, add `--socks5-server=localhost:1055` to
  `tailscaled` in the entrypoint and point tools at that proxy.
- **Weird linker errors** — never `set -x LD_LIBRARY_PATH` shell-wide: nix binaries and
  Ubuntu binaries each use their own glibc and must not see each other's libs. Scope it to
  the single command that needs it, if ever.
