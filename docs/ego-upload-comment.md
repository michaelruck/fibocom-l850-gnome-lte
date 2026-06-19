# Reviewer comment for the extensions.gnome.org upload

Paste the text below into the **"Comment for the reviewer"** field on the
<https://extensions.gnome.org/upload/> page when submitting the extension.
It explains the unusual (but necessary) privileged-helper design up front, so a
reviewer is not surprised by the `sudo`/`pkexec` calls.

---

Hi reviewers,

This extension is unusual, so a heads-up about its design.

It controls a **Fibocom L850-GL / Intel XMM7360 LTE modem**, which has **no working ModemManager/MBIM support** on Linux. The modem can only be driven through the proprietary userspace `xmm7360-pci` driver, which exposes a plain `wwan0` interface but no system service that the desktop could talk to. So instead of NetworkManager/ModemManager, the extension talks to a small set of **purpose-built, root-owned helper scripts** that ship alongside it:

- For status polling and toggling it runs `sudo -n /usr/local/bin/fibocom-l850-status` and `fibocom-l850-ctl on|off`. These are **whitelisted, argument-locked, passwordless `sudoers` entries** installed by the project — not generic shell access. The scripts only read the interface state / signal info and bring the `wwan0` link up or down.
- To change the APN, the preferences run `pkexec /usr/local/bin/fibocom-l850-apn <apn>`, guarded by a dedicated **polkit policy** (`org.fibocom.l850.set-apn`); the APN argument is validated against `^[A-Za-z0-9._-]+$`.

No code runs outside `enable()`/`disable()`, no network calls, no eval. All privileged logic lives in the audited helper scripts, not in the extension.

Full source, helpers, polkit policy and sudoers rules: https://github.com/michaelruck/fibocom-l850-gnome-lte

I understand shelling out to `sudo`/`pkexec` is normally discouraged. Here it's the only way to expose this otherwise-undriveable modem to the desktop. If that's a blocker for EGO, I completely understand — please let me know and I'll adjust. Thanks for your time!
