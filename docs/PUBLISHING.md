# Publishing the GNOME extension to extensions.gnome.org (EGO)

The extension can be installed straight from this repo (see the README), but you
can also submit it to [extensions.gnome.org](https://extensions.gnome.org) so
people can install it with one click.

## Build the submission archive

```bash
cd gnome-extension
gnome-extensions pack fibocom-l850-lte@michaelruck.github.io \
  --schema=schemas/org.gnome.shell.extensions.fibocom-l850-lte.gschema.xml \
  --force -o ..
```

This produces `fibocom-l850-lte@michaelruck.github.io.shell-extension.zip` in the
repo root. (It is git-ignored — it is a build artifact, not source.)

## Upload

1. Sign in at <https://extensions.gnome.org/accounts/login/> (create an account
   if needed).
2. Go to <https://extensions.gnome.org/upload/> and upload the `.zip`.
3. Wait for a human reviewer. They run the code and read it line by line.

## Heads-up for the review

This extension is unusual: it controls a piece of hardware that has **no
ModemManager support**, so it talks to small privileged helper scripts instead
of a system service. Reviewers will see two things worth a note in your upload
comment:

- It spawns `sudo -n /usr/local/bin/fibocom-l850-status` / `fibocom-l850-ctl`
  for status polling and toggling. These are whitelisted, argument-locked,
  passwordless `sudoers` entries installed by this project — not arbitrary shell
  access.
- It launches `pkexec /usr/local/bin/fibocom-l850-apn <apn>` to change the APN,
  guarded by a polkit policy.

Because EGO generally discourages extensions that shell out to `sudo`, approval
is **not guaranteed**. If a reviewer objects, the GitHub install path remains the
primary distribution channel and works fully. You can explain in the upload
comment that the helpers exist precisely because this modem cannot be driven by
ModemManager/NetworkManager.
