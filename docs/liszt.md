# liszt — ephemeral VastAI GPU host

`liszt` is not a real machine: it is a non-init OCI image built by
[nix2gpu](https://github.com/fleek-sh/nix2gpu) (`modules/machines/liszt.nix`), pushed by GitHub
Actions (`.github/workflows/liszt-image.yml`) to the **private** GHCR package
`ghcr.io/demic-dev/liszt`. A rented VastAI GPU instance runs it directly; on boot it joins the
tailnet as `liszt` using an **ephemeral** Tailscale authkey and serves **Tailscale SSH**. The
workflow is:

> rent → `ssh root@liszt` → work → destroy the instance

Because the authkey is ephemeral, the tailnet node removes itself shortly after the instance dies,
so the `liszt` name is free again for the next rental. Nothing secret is baked into the image — the
authkey is injected at runtime by the VastAI template.

nix2gpu ships CUDA (13.0), Tailscale, sshd and dev tooling; on top we bake our own home-manager
config (fish with bobthefish + git, same as satie/bach) plus `uv`, `python3`, `tmux`, `htop`,
`ripgrep`, `curl`. VastAI's nvidia runtime injection makes the host driver / `nvidia-smi` available;
manylinux wheels (torch, vLLM, …) are installed per session with `uv`.

## One-time setup

### 1. Tailscale admin console

1. In the ACL policy, define a tag and let yourself own it:

   ```jsonc
   "tagOwners": {
     "tag:gpu": ["autogroup:admin"],
   }
   ```

2. Allow yourself to SSH into tagged nodes as root (plain `accept`, not check mode — check mode
   would require a browser round-trip every session):

   ```jsonc
   "ssh": [
     { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:gpu"], "users": ["root"] },
   ]
   ```

3. Create an authkey (Settings → Keys → *Generate auth key*):
   **Reusable** ✓, **Ephemeral** ✓, **Pre-authorized** ✓, **Tags**: `tag:gpu`, expiry 90 days.
   This is the `TAILSCALE_AUTHKEY` value below. Rotate it when it expires. (The node registers as
   `liszt` regardless of VastAI's hostname — see the hostname note under *Deploy*.)

### 2. GitHub

- The image is pushed automatically by the `liszt image` workflow (push to `main` touching
  `modules/machines/liszt.nix`, `flake.nix` or the workflow, or *Run workflow* manually — see
  *Updating*). After the **first** run, check <https://github.com/demic-dev?tab=packages> →
  `liszt` → settings: it should be **private** (default for user-owned packages) and linked to the
  repo.
- CI push needs a **classic PAT** with the `write:packages` scope, stored as the repo secret
  `GHCR_TOKEN` (nix2gpu's `copyToGithub` authenticates through the `gh` CLI with it).
- For VastAI to *pull* the private image, a classic PAT with only `read:packages` is enough (can be
  the same token or a narrower one).

### 3. VastAI template

Create a template with:

| Field | Value |
|---|---|
| Image path/tag | `ghcr.io/demic-dev/liszt:latest` |
| Docker repository server | `ghcr.io` + your GitHub username + the `read:packages` PAT |
| Launch mode | **Docker ENTRYPOINT** (*not* SSH or Jupyter — those override the entrypoint and the tailscale/ssh bootstrap would never run) |
| Docker options | `-e TAILSCALE_AUTHKEY=tskey-auth-…` |
| Disk | ≥ 40 GB (model weights) |
| Ports | none needed (tailscale is outbound-only; port 22 is exposed only for the optional direct-sshd path) |

Optional Docker options:
- `-e TAILSCALE_HOSTNAME=<name>` — override the default `liszt` node name.
- `-e SSH_PUBLIC_KEYS="ssh-ed25519 …"` — install keys for the container's own sshd on port 22
  (a fallback to Tailscale SSH).
- `-e GIT_EMAIL=<email>` — commit email, applied automatically at startup. agenix can't decrypt on
  a throwaway host (no persistent recipient identity, and the image ships no secrets), so the email
  is injected here instead; the template persists, so it's a one-time setup.
- `-e GIT_NOREPLY_EMAIL=<id+user@users.noreply.github.com>` — used for `github.com` remotes when
  set, mirroring the real-vs-noreply routing on satie/bach (`GIT_EMAIL` stays the default).

## Build, test, push

Built with nix2gpu, so the image is addressed as the flake package `.#liszt` with helper apps:

```sh
nix build .#liszt                        # build the image (x86_64-linux only — see note)
nix run  .#liszt.copyToContainerRuntime  # local smoke test: load into docker/podman
nix run  .#liszt.copyToGithub            # push :latest to ghcr.io/demic-dev/liszt
```

> **Build host:** `.#liszt` is `x86_64-linux`; satie and bach are both aarch64, so neither can
> build it locally. The authoritative build is CI (GitHub Actions, x86_64). To build elsewhere you
> need an x86_64 machine/builder with these substituters enabled (they carry the CUDA / nix2gpu
> prebuilds; a from-source CUDA build is impractical):
> `weyl-ai.cachix.org`, `cuda-maintainers.cachix.org`, `ai.cachix.org`, `nix-community.cachix.org`
> (public keys are in `.github/workflows/liszt-image.yml`).

## Per-session workflow

1. Rent an instance from the template (filter on the GPU you need).
2. Watch the instance logs until the node joins the tailnet as `liszt`.
3. From satie/bach: `ssh root@liszt`. You land in fish; auth is your tailnet identity, no keys.
4. Committing works out of the box if `GIT_EMAIL` (and optionally `GIT_NOREPLY_EMAIL`) is set in the
   template — the startup hook writes `~/.gitconfig` with the same GitHub-noreply routing as
   satie/bach. Without it, set one per session: `git config --global user.email <email>`.
5. Python/GPU work — **always use uv-managed Python, never the nix `python3`**:

   ```sh
   uv python install 3.12
   uv venv ~/venv && source ~/venv/bin/activate.fish
   uv pip install vllm        # or torch, llama-cpp-python, …
   ```

   uv's interpreters use a non-nix dynamic loader, so wheels find the host-injected `libcuda.so.1`
   that VastAI provides. The nix `python3` is for scripting, not GPU wheels.
6. Run long jobs inside `tmux`.
7. Destroy the instance when done. The tailnet node disappears on its own (ephemeral key); the name
   is reusable immediately-ish (see troubleshooting if not).

## Updating the image

- Any push to `main` touching `modules/machines/liszt.nix`, `flake.nix` or the workflow rebuilds
  and pushes `:latest`. VastAI pulls `:latest` on the next rental.
- Changes that also shape the image but are **not** triggers (to avoid churn): the `fish`/`git`
  home modules and `flake.lock` (nixpkgs / home-manager / nix2gpu bumps). Run the workflow manually
  (*Actions → liszt image → Run workflow*) after touching those.
- **CUDA version** is nix2gpu's default (13.0). torch/vLLM wheels bundle their own CUDA runtime and
  rely on the VastAI-injected driver, so the toolkit version mostly matters for source builds
  (nvcc). If a wheel needs a specific CUDA, install a matching `nvidia-*-cu13` wheel inside the uv
  venv, or pin `cuda.packages` in `modules/machines/liszt.nix`.

## Troubleshooting

- **Node shows up as `liszt-1`** — the previous ephemeral node hasn't been reaped yet. Delete it in
  the admin console, or run `tailscale logout` on liszt before destroying the instance.
- **Node registers under VastAI's hostname, not `liszt`** — the in-image
  `tailscale set --hostname=liszt` runs once the backend is up; check the instance logs for it. You
  can also pass `--hostname liszt` in the VastAI Docker options if the platform honors it.
- **Container exits / never joins** — `TAILSCALE_AUTHKEY` unset or expired. Check the VastAI
  instance logs and the key's expiry in the admin console.
- **`ssh root@liszt` refused** — check the SSH ACL rule (`tag:gpu`, user `root`) and
  `tailscale status` on satie. The node must be visible and tagged (the authkey carries `tag:gpu`).
- **No GPU / `nvidia-smi` missing** — VastAI's nvidia runtime injection failed; check the template's
  GPU filters and the instance type.
- **Can't reach other tailnet hosts *from* liszt** — expected: tailscaled runs in userspace
  networking mode (no `/dev/net/tun` in VastAI containers), which handles inbound fine but not
  outbound into the tailnet.
