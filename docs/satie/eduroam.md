# eduroam on satie

satie connects to eduroam at the University of Milan through a NetworkManager profile declared in the flake. This page covers the profile, its secret, and what to check when it fails.

> [!NOTE]
> The profile hasn't been tested on campus yet.

## Profile

`modules/hosts/satie/eduroam.nix` declares the profile with `networking.networkmanager.ensureProfiles`:

| Setting | Value |
|---|---|
| EAP method | PEAP, with MSCHAPv2 inside |
| CA certificate | `modules/hosts/satie/eduroam-unimi-ca.pem` |
| Server name check | `domain-match = "eduroam.unimi.it"` |
| Identity, password | from the agenix secret `eduroam` |

The CA certificate and settings come from eduroam CAT, the official configuration service, for unimi's profile. The certificate is public.

NetworkManager uses iwd as its Wi-Fi backend (`modules/hosts/satie/network.nix`). It converts the profile for iwd itself.

## Secret

`secrets/eduroam.age` is encrypted to satie and michele@satie, and holds exactly two lines:

```
EDUROAM_ID=name.surname@studenti.unimi.it
EDUROAM_PASSWORD='the password'
```

NetworkManager substitutes them into the profile through `environmentFiles`. The password is stored with the profile, so no secret agent has to answer a prompt.

The single quotes protect special characters. A backslash in the password must be written twice (`\\`), because the profile format treats `\` as an escape.

To change it, from `secrets/`:

```sh
agenix -e eduroam.age
```

## When it fails

Watch the logs while connecting:

```sh
journalctl -f -u iwd -u NetworkManager
nmcli connection up eduroam
```

- TLS or certificate errors: likely the conversion to iwd losing a setting such as `domain-match`. Try the wpa_supplicant backend (below).
- Authentication rejected: compare the identity's format with the one on a phone that works.

To test without rebuilding, the eduroam-flake creates a hand-made profile from the same CAT data:

```sh
nix run github:MayNiklas/eduroam-flake#install-eduroam-unimi
nmcli --ask connection up eduroam
```

That leaves two profiles named eduroam. Delete one afterwards with `nmcli connection delete <uuid>`.

<details>
<summary>Why not the wpa_supplicant backend?</summary>

It's what eduroam CAT targets, and it's the fallback if iwd can't handle the profile: set `networking.networkmanager.wifi.backend` back to its default. It stays second choice because it caused problems on this Wi-Fi chip before. After switching, re-test home Wi-Fi, the phone hotspot, Wi-Fi with Bluetooth audio playing, and resume from sleep.

</details>
