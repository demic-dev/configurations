# Network and exposure

What on bach is reachable from where, and how that's enforced: DNS, nginx's default deny, Cloudflare's client certificates, and the Tailscale policy.

## Domains

bach serves two domains, both on Cloudflare DNS with wildcard records:

| Domain | Record | Resolves to |
|---|---|---|
| public | `*.<public>`, proxied | Cloudflare's IPs, which forward to bach |
| internal | `*.<internal>`, DNS only | bach's tailnet address |

Any new subdomain resolves without touching DNS. Certificates come from Let's Encrypt through a DNS-01 challenge with a Cloudflare token, one wildcard certificate per domain (`modules/services/acme.nix`). Vhosts use them with `useACMEHost`.

## Default deny

nginx denies every request that doesn't come from the tailnet or from bach itself. The rule sits once, at the `http` level, in `modules/services/nginx.nix`:

```nginx
allow 100.64.0.0/10;
allow fd7a:115c:a1e0::/48;
allow 127.0.0.1;
allow ::1;
deny all;
```

Every server and location block inherits it. A block that's public opts out with its own `allow all;`. In nginx, any `allow` or `deny` in a block replaces the inherited list completely, so one line is enough.

A new service is private unless its file says otherwise. A request for an unknown host name gets no answer at all: the catch-all vhost `_` closes the connection (`return 444`) and refuses the TLS handshake.

The `http` to `https` redirects keep working for everyone, because `return 301` runs in nginx's rewrite phase, before access checks.

<details>
<summary>Why not an allow list in each private vhost?</summary>

That's how it used to be, and it fails open: a vhost without the block is public. calibre-web and OnlyOffice ended up public that way. With the deny at the top, forgetting something keeps it private.

</details>

## What's public

| Vhost | Public part | File |
|---|---|---|
| Website and `www` | everything | `modules/services/hugo.nix` |
| Static files | regular files only: no listing, no dotfiles, no symlinks | `modules/services/static-files.nix` |
| Immich (public domain) | share links and the API routes they use | `modules/services/immich.nix` |
| Nextcloud (public domain) | share links and the routes their page uses | `modules/services/nextcloud.nix` |
| calibre-web (public domain) | `/opds` only | `modules/services/calibre.nix` |

Immich, Nextcloud and calibre-web each have a second vhost on the internal domain, with the full app.

Immich's public vhost answers `/` with 404 and proxies only `/share/`, `/s/`, `/_app/`, a few static files, and an API regex built from the shared-link routes in Immich's source. It accepts only GET, HEAD and POST. `server.externalDomain` stays the public domain, so links created in the app point there. The apps on phones use the internal domain.

Nextcloud's public vhost has the same subdomain as the internal one. It answers `/` with 404 and passes on only what a share page needs, for a single file, a folder, a password-protected share and a file drop: `/s/<token>` (the page, the password form, downloads), `/public.php/dav/files/<token>` and `/public.php/dav/uploads/<token>` (listing, downloads, file drop uploads), previews, the CSRF token, theming, and the public routes of the text editor and the PDF viewer. JS, CSS, images and fonts under `/core`, `/dist` and the shipped apps' asset folders come straight from Nextcloud's webroot, matched by file extension. Everything else is 404, including `/login`, `/remote.php`, `/ocs`, avatars and "Add to your Nextcloud". A URI with a `.` or `..` segment is refused too: nginx forwards the raw URI, and Nextcloud's router doesn't resolve them, so `/ocm/../s/<token>` would pass the check here and reach `/ocm/` there. The DAV routes accept the WebDAV methods uploads need; the rest only GET, HEAD, POST and PUT.

The vhost proxies to the internal one through `127.0.0.1`, with `X-Forwarded-Host` set to the public name. Nextcloud trusts that header only from `127.0.0.1` (`trusted_proxies`), so it builds the page's links with the public domain, which is in `trusted_domains`. The visitor's address comes from Cloudflare's `CF-Connecting-IP` header, trusted from any address in this vhost only, since nothing but Cloudflare gets past `ssl_verify_client`. Nextcloud receives it as `X-Forwarded-For` and throttles wrong share passwords per visitor, not for everyone at once.

Office files from a public link are download-only: the eurooffice app's scripts aren't served on the public domain, and the document server stays internal. Uploads go in 50 MiB chunks (`files.chunked_upload.max_size`), below the 100 MB Cloudflare accepts per request.

Nextcloud's "Copy link" button takes the host from the browser's address bar, so a link copied on the tailnet carries the internal domain. Replace it with the public domain before sending the link.

<details>
<summary>Why not make all of Nextcloud public?</summary>

It would put the login page, WebDAV and every app's API on the internet, for the sake of share links. The allow list keeps the public part to the share routes, and the clients keep using the tailnet.

</details>

calibre-web's public vhost proxies only `/opds`, the catalogue KOReader reads. OPDS uses HTTP basic auth, which makes it the only public login on bach. It's used only by dedicated calibre-web users with download permission and nothing else, so a leaked password exposes the books, not an admin account.

## Shared files

The fish function `share` (`modules/dev/fish.nix`) publishes a file through the static files vhost at `/<id><ext>`, lists what it published (`--list`), and deletes an entry by id (`--delete`). The id is 8 characters of `a-z0-9` (about 41 bits) read from `/dev/urandom`. The URL is the only access control: anyone who has it can download the file. The commands are in [Shell reference](../shell.md).

`<ext>` is the source file's last extension in lower case, kept only if it is 1 to 10 characters of `a-z0-9`, so `report.tar.gz` becomes `<id>.gz`. It gives the browser the content type, so PDFs and images open inline; a share without one is served as `application/octet-stream` and downloads. The original file name is not kept.

The content goes over `ssh bach` on stdin, and since michele's shell on bach is fish, the file is written with fish's `>?` redirection, which fails instead of overwriting an existing file. It lands flat in `/data/static-files/` with mode 0640 and the `static-files` group that nginx reads through. `--list` and `--delete` only see regular files at the top level whose name is an id plus an optional extension, so `resume.pdf`, `resume-ATS.pdf` (published by the `cv-resume` service in `modules/services/static-files.nix`) and anything else there are out of their reach.

## Cloudflare only

Public vhosts accept only requests that come through Cloudflare. They carry `ssl_verify_client on;`, and nginx checks the client certificate against Cloudflare's origin-pull CA (`modules/services/cloudflare-origin-pull-ca.pem`). This is Cloudflare's Authenticated Origin Pulls, enabled in the dashboard, with SSL mode set to Full (strict). In Flexible mode Cloudflare talks plain HTTP to bach, and the certificate check never happens.

Without it, anyone could connect to bach's IP with any Host header and skip Cloudflare's WAF, rate limits and DDoS protection.

The certificate is shared by every Cloudflare customer. It proves a request came through Cloudflare, not through this zone, so it stops direct scanners but not someone with their own Cloudflare account pointed at bach.

> [!WARNING]
> Cloudflare's origin-pull CA expires on 1 November 2029. Replace `modules/services/cloudflare-origin-pull-ca.pem` with the new one from https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem before then, or every public site starts answering 400.

When turning this on from scratch, enable it in Cloudflare first and deploy nginx second. In the other order, every public site is down in between.

<details>
<summary>Why not firewall 80 and 443 to Cloudflare's IP ranges?</summary>

It works, but the ranges change, and the list would have to be kept up to date by hand. The certificate check needs nothing until 2029.

</details>

<details>
<summary>Why not a Cloudflare Tunnel?</summary>

cloudflared hands every request to nginx from `127.0.0.1`, which the allow list trusts. The default deny would stop protecting anything on the public domain.

</details>

<details>
<summary>Why not fail2ban?</summary>

Behind Cloudflare, nginx and the apps see Cloudflare's addresses, so a ban hits a Cloudflare edge and everyone behind it, or nothing. Every login except OPDS and Nextcloud's share passwords is behind the tailnet anyway, and Nextcloud throttles share passwords itself, per visitor.

</details>

## Open ports

| Port | What |
|---|---|
| TCP 80, 443 | nginx |
| TCP 2222 | ssh in the initrd, only while bach waits for the disk passphrase (see [Disk and boot](disk.md)) |
| UDP 41641 | Tailscale direct connections; without it, traffic falls back to the slower DERP relays |

The services themselves listen on loopback.

## SSH

OpenSSH doesn't run on bach. SSH goes through Tailscale SSH, served by tailscaled on port 22 of the tailnet address (`--ssh` in `modules/services/tailnet-server.nix`). The Tailscale policy decides who may log in, and it's michele only. If Tailscale breaks, the way in is the VPS provider's VNC console.

## Tailscale policy

The tailnet's access policy is kept in `secrets/sensitive/tailscale-policy.hujson.age`, encrypted with git-agecrypt because it contains people's logins and the tailnet's addresses. Nothing reads it automatically: after editing, paste the plain file into the Tailscale admin console, which validates it and runs its tests.

michele's devices reach everything. Other people are members of `group:family`, which reaches `bach:443` and nothing else: not satie, not michele's phone, no SSH. The policy's tests make the console refuse a change that breaks these rules. After the tailnet, each service decides what they see through its own accounts.

Through nginx, family members also reach the login pages of the internal services they have no accounts on. The policy can't narrow that down, since everything shares port 443.

To add or remove a person, use the `tailnet-person` skill (`.claude/skills/tailnet-person/SKILL.md`).

<details>
<summary>Why not Tailscale's GitOps action?</summary>

It needs the policy file in plain text in the repository. For a file that changes this rarely, pasting it by hand is less work than making that safe.

</details>

## Check what's exposed

From a machine off the tailnet:

```sh
nmap -Pn -p- <bach's public IP>     # 80 and 443 only, plus 2222 while unlocking
curl -k --resolve <internal name>:443:<bach's public IP> https://<internal name>/    # 403
curl --resolve <public name>:443:<bach's public IP> https://<public name>/           # 400: no Cloudflare client certificate
```

The second test matters most: the Host header is free, so every internal name has to refuse a request that arrives at the public IP.

From a phone on mobile data with Tailscale off: the website works, an Immich share link opens and plays videos, the Immich public domain's `/` gives 404, a Nextcloud share link opens (with the domain swapped) while `/`, `/login` and `/remote.php/dav` on the same host give 404, and calibre's `/opds` asks for credentials.
