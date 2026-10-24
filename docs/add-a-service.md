# Add a service or a host

How to add a service, an app or a host, and the conventions a new module follows.

## Add a service

Create one file in the folder it belongs to, usually `modules/services/`. A service on bach looks like this:

```nix
{ ... }:
{
  flake.nixosModules.example =
{ env, ... }:
let
  internal = env.cloudSettings.internal;
  domain = "${env.cloudSettings.services.example.subdomain}.${internal}";
  port = env.cloudSettings.services.example.port;
in
{
  services.example = {
    enable = true;
    listenAddress = "127.0.0.1:${toString port}";
  };

  # Nginx
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;
    useACMEHost = internal;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:${toString port}";
  };

  # Persistence
  environment.persistence."/persist".directories = [ "/var/lib/example" ];
}
  ;
}
```

Then:

1. Add its subdomain and port to `cloudSettings.services` in `env.nix`.
2. Add `example` to bach's list in `modules/hosts/bach/default.nix`.
3. `git add` the new file. Flakes only see tracked files.
4. Evaluate on satie, then deploy (see [Build and deploy](deploy.md)).

Keep everything the service needs in that file: its vhost, database, Redis, secrets, backup job and persistence lines.

## Conventions

The service listens on loopback only. nginx is the only thing facing the network.

A vhost on the internal domain is reachable from the tailnet only, with nothing to add: the `*.<internal>` DNS record and certificate already cover any subdomain. To make a vhost public, add both lines to its `extraConfig`:

```nginx
allow all;
ssl_verify_client on;
```

nginx only accepts `ssl_verify_client` for a whole server, not for a location. To publish part of a service, make the whole public vhost answer 404 except the locations that should be reachable, as `modules/services/calibre.nix` and `modules/services/immich.nix` do.

See [Network and exposure](bach/network.md) before doing that.

State that must survive a reboot goes in `environment.persistence."/persist"`, in the service's own file. Caches don't: `/var/cache` and `/tmp` are already on disk (see [Memory](bach/memory.md)).

Pin the uid and gid of any user or group that owns persisted files:

```nix
users.users.example.uid = 988;
users.groups.example.gid = 988;
```

`/var/lib/nixos`, where NixOS remembers the ids it handed out, isn't persisted on bach. Without a pinned id, a change to the user list can give the service a different uid after a reboot, and it loses access to its own files. The impermanence module warns at evaluation about any user or group left without one.

Secrets go in agenix, declared in the same file. See [Secrets](secrets.md).

## Add a desktop app

Apps for michele go in a home-manager aspect (`flake.homeModules.<name>`) or straight into `home.packages` in `modules/hosts/satie/users.nix`. A home aspect is imported from the `imports` list in that same file, not from `default.nix`.

## Turn something off

Comment out or remove its name in the host's list. The file stays, ready to come back. Its persisted data on bach stays in `/persist` until removed by hand.

## Add a host

1. Create `modules/hosts/<host>/` with a `default.nix` that defines `flake.nixosConfigurations.<host>`, using bach's or satie's as a template.
2. Add a `userSettings.<host>` block to `env.nix`.
3. If the host doesn't have `/persist`, import `impermanence` anyway and set `environment.persistence."/persist".enable = false`. That keeps the persistence lines of shared aspects valid and inert, as on satie.
4. For secrets: add the host's ssh public key to `secrets/secrets.nix`, add it to the secrets it needs, and rekey. To read `secrets/sensitive/`, the host needs the git-agecrypt key. See [Secrets](secrets.md).
