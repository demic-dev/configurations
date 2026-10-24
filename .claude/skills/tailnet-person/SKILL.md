---
name: tailnet-person
description: Give a relative, partner or friend access to bach's services (Immich, Nextcloud…) over Tailscale, or take it away. Use when Michele says "add <name> to the tailnet", "give <name> access to Immich", "remove <name>", or similar.
---

# Add or remove a person on the tailnet

People other than Michele are **members** of the tailnet in `group:family`. The policy lets them reach `bach:443` (nginx) and nothing else: not satie, not Michele's phone, no SSH. The services decide what they see after that, through their own accounts.

The policy lives in `secrets/sensitive/tailscale-policy.hujson.age`. git-agecrypt encrypts it on commit, so the working tree has plain HuJSON and GitHub has ciphertext. Nothing on the hosts reads it: Michele pastes it into the Tailscale admin console, which validates it and runs its tests.

## Adding someone

1. **Michele invites them** (admin console → Users → Invite users). They install Tailscale, log in and accept the invite. You can't do this step.
2. **Find their login name.** Their devices show up as peers once they've joined:
   ```sh
   tailscale status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); u=d["User"]; [print(p["HostName"], u[str(p["UserID"])]["LoginName"]) for p in d["Peer"].values()]'
   ```
   Ask Michele which login is the new person. Don't guess from device names.
3. **Edit the policy:**
   - Add the login to `group:family`.
   - Add a line to `tests`, the same shape as the existing family ones: accept `bach:443`, deny `bach:22`, `bach:80` and `satie:22`.
   - Add a line to `sshTests` denying `root` and `michele` on bach.
   - Never add them to a grant of their own, and never touch Michele's grant or the `ssh` rule. If someone needs more than `bach:443`, stop and discuss it with Michele first.
4. **Check that the file is still encrypted for GitHub** before suggesting a commit:
   ```sh
   git check-attr filter secrets/sensitive/tailscale-policy.hujson.age   # → filter: git-agecrypt
   git add secrets/sensitive/tailscale-policy.hujson.age
   git show :secrets/sensitive/tailscale-policy.hujson.age | head -c 21   # → age-encryption.org/v1
   ```
   If either check fails, unstage the file and stop. A plaintext policy on a public repo exposes the people's logins and the tailnet's addresses.
5. **Hand over to Michele:** show the diff and ask before committing. Michele pastes the plain file into the console. If the console rejects it, fix the file together, never by loosening a test.
6. **Service accounts** are Michele's job, done in each service's admin UI (Immich: Administration → Users). The apps' server URL is the **internal** domain (`<service>.<internal>`), not the public one: the public Immich domain only serves share links.

## Removing someone

Remove their login from `group:family`, their `tests` and `sshTests` lines, then do steps 4–5. Remind Michele to remove the user in the admin console too: that also logs out their devices. Their service accounts are a separate decision; ask.

## Don't

- Don't call the Tailscale API or apply the policy yourself. There's no API key on purpose.
- Don't print the policy anywhere that ends up outside this machine (issues, PR descriptions, commit messages).
- Don't use node sharing for new people: everyone is a member in `group:family`, so one policy covers them all.
