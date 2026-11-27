{ ... }:
let
  # Shows a command's output only if it fails.
  run = ''
    run() {
      local out
      out=$("$@" 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
    }
  '';
in
{
  # satie updates the inputs at night, with nixpkgs at the newest commit Hydra has built what the hosts need,
  # builds both hosts, copies bach's system to bach and switches itself. bach switches to what satie copied.
  flake.nixosModules.auto-update-build =
    { config, lib, pkgs, env, ... }:
    let
      key = env.userSettings.satie.ssh.auto-update.location;
      repo = env.userSettings.satie.configPath;
      user = env.userSettings.satie.user;
      state = "${env.userSettings.satie.home.path}.local/state/auto-update";
      remote = "${env.userSettings.bach.user}@bach";

      # Packages the hosts need that must come from the cache, never be built here: they don't fit in memory
      # (Chromium and Electron need far more than satie's 8 GB) or take hours. Electron was OOM-killed on bach
      # on 26 Nov 2026. Matched against derivation names in the build plan: <name>-<version>.drv, so
      # <name>-<version>-fish-completions.drv, built locally for every package, doesn't count.
      heavy = [
        # browser engines, and the apps built on them
        "chromium-unwrapped"
        "electron-unwrapped"
        "qtwebengine"
        "webkitgtk"
        "signal-webrtc"
        "signal-desktop"
        "bitwarden-desktop"
        # compilers and runtimes
        "gcc"
        "llvm"
        "clang"
        "rustc"
        "ghc"
        "zig"
        "openjdk"
        "openjdk-headless"
        "nodejs"
        "nodejs-slim"
        "pandoc"
        # immich's machine learning, on bach
        "immich"
        "onnxruntime"
        "python3.[0-9]+-torch"
      ];

      build = pkgs.writeShellApplication {
        name = "auto-update-build";
        runtimeInputs = [
          config.nix.package
          pkgs.git
          pkgs.git-agecrypt
          pkgs.openssh
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.curl
          pkgs.jq
        ];
        text = run + ''
          export NIX_SSHOPTS="-i ${key} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=30"
          mkdir -p ${state}

          # A worktree of your checkout, so the job never touches the files you work on.
          work=${state}/nixos
          if [ ! -e "$work" ]; then
            run git -C ${repo} worktree prune
            run git -C ${repo} worktree add --detach "$work" main
          fi
          cd "$work"
          run git checkout --force --detach main
          # A failed run puts flake.lock back.
          trap 'git checkout --quiet -- flake.lock' EXIT

          toplevel() {
            nix eval --raw ".#nixosConfigurations.$1.config.system.build.toplevel.outPath"
          }

          # Stops if a host may run something deployed by hand and not committed, which switching would roll back.
          # A host passes if it runs what the last run gave it, if it switched before main's newest commit (main
          # supersedes that deploy), or if it runs what main builds. Store paths depend only on content, so a deploy
          # from a dirty tree matches the commit that follows it, as long as system.configurationRevision stays unset.
          # The mtime of /run/current-system is when the host switched to it.
          main_time=$(git log -1 --format=%ct main)
          check() {
            if [ "$2" = "$(cat "${state}/$1-last" 2>/dev/null)" ] || [ "$3" -lt "$main_time" ]; then
              return 0
            fi
            if [ "$2" != "$(toplevel "$1")" ]; then
              echo "$1 runs $2, deployed after main's newest commit and not built by main: commit it or deploy main" >&2
              return 1
            fi
          }
          # shellcheck disable=SC2086
          running_bach=$(ssh $NIX_SSHOPTS ${remote} readlink -f /run/current-system)
          # shellcheck disable=SC2086
          switched_bach=$(ssh $NIX_SSHOPTS ${remote} stat -c %Y /run/current-system)
          check bach "$running_bach" "$switched_bach"
          check satie "$(readlink -f /run/current-system)" "$(stat -c %Y /run/current-system)"

          read -r installed_rev installed_time < <(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked | "\(.rev) \(.lastModified)"' flake.lock)

          # The nixpkgs commits Hydra has evaluated since the one the hosts run, newest first. Hydra evaluates
          # one every 8 to 9 hours and lists the last 20; the answer is about 40 MB, since it names every build.
          revs=$(curl -fsSL -m 600 -H 'Accept: application/json' https://hydra.nixos.org/jobset/nixpkgs/unstable/evals \
            | jq -r --argjson t "$installed_time" '.evals[] | select(.timestamp > $t) | .jobsetevalinputs.nixpkgs.revision')

          # Takes the newest commit whose build plan has nothing heavy to build: Hydra has built it all, or it's
          # already here. Fresh evaluations are usually skipped, since Hydra needs a day or so to build them.
          run nix flake update
          chosen=
          skipped=
          for rev in $revs; do
            if [ "$rev" = "$installed_rev" ]; then break; fi
            run nix flake lock --override-input nixpkgs "github:nixos/nixpkgs/$rev"
            if ! plan=$(nix build --dry-run .#nixosConfigurations.{bach,satie}.config.system.build.toplevel 2>&1); then
              printf '%s\n' "$plan" >&2
              exit 1
            fi
            found=$(grep -oE '/nix/store/[a-z0-9]{32}-(${lib.concatStringsSep "|" heavy})-[0-9][^ /-]*\.drv' <<<"$plan" || true)
            if [ -z "$found" ]; then
              chosen=$rev
              break
            fi
            printf 'skipping nixpkgs %s, it would build:\n%s\n' "''${rev:0:7}" "$found" >&2
            skipped=1
          done
          # No newer commit fits: the inputs stay as they are, and the hosts still get main's config.
          if [ -z "$chosen" ]; then
            git checkout --quiet -- flake.lock
            if [ -n "$skipped" ]; then
              echo "no newer nixpkgs commit fits, keeping ''${installed_rev:0:7}" >&2
            fi
          fi

          # The raw log format prints "building '<drv>'..." as each build starts, so the journal shows what's
          # building. The grep drops the paths fetched from the cache and the lists of paths: hundreds of lines.
          for host in bach satie; do
            nix build --log-format raw --out-link "${state}/$host-system" ".#nixosConfigurations.$host.config.system.build.toplevel" 2>&1 \
              | { grep --line-buffered -v -e "^copying path '" -e '^  /nix/store/' || true; }
          done

          # bach fetches what the cache has itself; only what was built here crosses the network. Those paths
          # are unsigned: without --no-check-sigs bach refuses them ("lacks a signature by a trusted key"), and
          # it honours the flag because michele is a trusted user there (trusted-users in core.nix). The link goes
          # once the copy is done, so the cleanup after the switch removes bach's system from satie's store.
          bach_system=$(readlink -f "${state}/bach-system")
          run nix copy --to "ssh-ng://${remote}" --substitute-on-destination --no-check-sigs "$bach_system"
          rm "${state}/bach-system"

          if ! git diff --quiet flake.lock; then
            run git commit -m "chore(flake): update inputs" flake.lock
          fi
          # The lock commit reaches your main only when your checkout is on main with no changes. HEAD here is the
          # worktree's: with -C ${repo} it would be your checkout's, and the lock commit would be left behind.
          run git branch --force auto-update HEAD
          if [ "$(git -C ${repo} branch --show-current)" = main ] && [ -z "$(git -C ${repo} status --porcelain)" ]; then
            run git -C ${repo} merge --ff-only auto-update
          elif ! git -C ${repo} merge-base --is-ancestor auto-update main; then
            echo "${repo} is not on a clean main: the lock commit waits on branch auto-update" >&2
          fi

          # bach switches as soon as this file changes (auto-update-apply below).
          # shellcheck disable=SC2086
          ssh $NIX_SSHOPTS ${remote} 'mkdir -p .local/state/auto-update && cat > .local/state/auto-update/for-bach' <<<"$bach_system"
          echo "$bach_system" > "${state}/bach-last"
          readlink -f "${state}/satie-system" > "${state}/satie-last"
        '';
      };

      switch = pkgs.writeShellApplication {
        name = "auto-update-switch";
        runtimeInputs = [ config.nix.package pkgs.coreutils config.systemd.package ];
        text = run + ''
          new=$(readlink -f "${state}/satie-system")
          if [ "$new" != "$(readlink -f /run/current-system)" ]; then
            run nix-env -p /nix/var/nix/profiles/system --set "$new"
            run "$new/bin/switch-to-configuration" switch
          fi
          systemctl start --no-block cleanup.service
        '';
      };
    in
    {
      age.secrets.auto-update-at-satie = {
        file = ../../secrets/auto-update-at-satie.age;
        path = key;
        owner = user;
        group = "users";
        mode = "600";
      };

      systemd.services.auto-update = {
        description = "Update the flake's inputs, build both hosts, copy bach's system and switch satie";
        startAt = "*-*-* 03:00:00";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        # Only on the charger, and no catching up after a night asleep (no Persistent=), so it never runs
        # during the day.
        unitConfig.ConditionACPower = true;
        # The switch runs inside this unit: restarting it would kill the switch halfway.
        restartIfChanged = false;
        unitConfig.X-StopOnRemoval = false;
        serviceConfig = {
          Type = "oneshot";
          # Holds off noctalia's idle suspend. Closing the lid still suspends (LidSwitchIgnoreInhibited=yes,
          # logind.conf(5)). The build runs as michele: the worktree, the git-agecrypt key and the key for
          # bach are his.
          ExecStart = "${config.systemd.package}/bin/systemd-inhibit --what=sleep --who=auto-update --why='Building the next systems' ${pkgs.util-linux}/bin/runuser -u ${user} -- ${build}/bin/auto-update-build";
          ExecStartPost = "${switch}/bin/auto-update-switch";
        };
      };
    };

  # bach switches to the system satie copied into its store, as soon as satie writes its path.
  flake.nixosModules.auto-update-apply =
    { config, pkgs, env, ... }:
    let
      forBach = "${env.userSettings.bach.home.path}.local/state/auto-update/for-bach";

      apply = pkgs.writeShellApplication {
        name = "auto-update-apply";
        runtimeInputs = [ config.nix.package pkgs.coreutils config.systemd.package ];
        text = run + ''
          new=$(cat ${forBach})
          if [ "$new" = "$(readlink -f /run/current-system)" ]; then
            exit 0
          fi
          # satie names the path: switch only to a system built for bach.
          if [ "$(cat "$new/etc/hostname" 2>/dev/null)" != bach ]; then
            echo "$new is not a system for bach" >&2
            exit 1
          fi
          run nix-env -p /nix/var/nix/profiles/system --set "$new"
          run "$new/bin/switch-to-configuration" switch
          systemctl start --no-block cleanup.service
        '';
      };
    in
    {
      systemd.paths.auto-update = {
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = forBach;
      };
      systemd.services.auto-update = {
        description = "Switch to the system satie built for bach";
        # The switch runs inside this unit: restarting it would kill the switch halfway.
        restartIfChanged = false;
        unitConfig.X-StopOnRemoval = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${apply}/bin/auto-update-apply";
        };
      };
    };
}
