# poco

How the notes receive what the poco phone app sends: the applier on bach, its triggers and its state.

The phone never edits the Markdown. It uploads one small JSON file per event (a capture, a task done, the day's pick) to `notes/_events/` in Nextcloud. The applier reads each event, edits `inbox.md`, `today.md`, `done.md` or a `TODO.md` accordingly, and deletes the event. The applier, its module and the event format live in the poco repository; `modules/services/poco.nix` imports its `hosting` module through the `poco` flake input and sets the URL, the user and the secret.

## Triggers

A path unit watches the `_events` folder on disk and starts `poco-applier.service` when an event lands. A timer starts it every 5 minutes as well, for anything the path unit missed. The service runs until `_events/` is empty.

## WebDAV, not the disk

The applier reads and writes through WebDAV on the internal Nextcloud vhost, never the files under `/data/nextcloud`. Nextcloud then updates its ETags, keeps file versions and tells the desktop clients. Each write carries `If-Match` with the ETag it read: if the laptop synced an edit in between, Nextcloud answers 412 and the applier reads the file again. A line the applier can no longer find becomes a note in `inbox.md`.

It authenticates with a Nextcloud app password, the agenix secret `secrets/poco_app_pass.age`, passed to the service as a systemd credential.

## State

The service runs as a dynamic user. `/var/lib/private/poco/state.json` keeps the ids of events applied in the last 30 days, so an event the phone uploads twice is applied once, and how far the current event got, so a crash in the middle resumes there. `/var/lib/private` is persisted as a whole, with mode 0700: systemd refuses to set up a dynamic user's state directory under it with looser permissions.

## Check it

```bash
systemctl status poco-applier.path poco-applier.timer
journalctl -u poco-applier
```
