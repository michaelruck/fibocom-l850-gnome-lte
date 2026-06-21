# Why this extension isn't on extensions.gnome.org (EGO)

Install the extension straight from this repo (see the README) — that is the
**primary and only** distribution channel. It is **not** available on
[extensions.gnome.org](https://extensions.gnome.org), and this page explains why,
because the reasons are useful if you maintain a similar hardware extension.

The extension was submitted to EGO once and **rejected**. Two independent rules
block it, and both are reasonable:

## 1. Extensions may not call `sudo` / `pkexec`

EGO does not allow an extension to spawn privileged helpers like `sudo` or
`pkexec`. Extension code runs inside the `gnome-shell` process, and escalating
privileges from there is exactly the kind of thing the review process exists to
keep out.

This extension does it on purpose: the Fibocom L850 / XMM7360 has **no
ModemManager support**, so there is no system service the desktop can talk to.
The extension therefore drives small, argument-locked, root-owned helper scripts:

- `sudo -n /usr/local/bin/fibocom-l850-status` / `fibocom-l850-ctl on|off` for
  status polling and toggling (passwordless, whitelisted `sudoers` entries — not
  arbitrary shell access);
- `pkexec /usr/local/bin/fibocom-l850-apn <apn>` to change the APN, guarded by a
  polkit policy.

The EGO-compliant way to do this would be to move all privileged logic into a
**systemd D-Bus system service** and have the extension talk to it only over
D-Bus (authorised via polkit), so the extension never escalates anything itself.
That is a sizeable rewrite and is not currently done here.

## 2. Extensions must not be AI-generated

EGO recently introduced a rule that
[extensions must not be AI-generated](https://gjs.guide/extensions/review-guidelines/review-guidelines.html#extensions-must-not-be-ai-generated).
Much of this code was written with heavy AI assistance, so — honestly — it falls
under that rule, and we are not going to pretend otherwise. The rule exists
because the small reviewer team was being flooded with unmaintainable,
un-understood AI submissions; that is a fair thing to defend against, even though
it also catches genuinely tested, maintained projects like this one.

## So: install from GitHub

Both rules together mean EGO is not a realistic target for this extension without
a from-scratch, hand-written rewrite *and* a re-architecture away from
`sudo`/`pkexec`. For a niche, hardware-specific toggle that is not worth it. The
`install.sh` path in this repo installs the extension to your user extensions
directory and works fully — you just don't get the one-click EGO button.
