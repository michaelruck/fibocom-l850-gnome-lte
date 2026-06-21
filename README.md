# fibocom-l850-gnome-lte

**Get the Fibocom L850-GL / Intel XMM7360 LTE modem working on Linux — with a
GNOME Quick Settings toggle for mobile data, signal strength and APN.**

This is the missing user-facing layer on top of the
[xmm7360-pci](https://github.com/xmm7360/xmm7360-pci) userspace driver:
a boot service that brings the modem online, small helper scripts, and a GNOME
Shell extension that adds a **Mobile Data** toggle to Quick Settings (just like
the Wi-Fi switch) showing operator, RAT and signal in dBm.

Found on hardware such as the **Lenovo IdeaPad Duet 3 (10IGL5 LTE)** and many
other laptops shipping the Fibocom L850-GL (PCI ID `8086:7360`).

![The Mobile Data toggle in the GNOME Quick Settings panel, showing operator, RAT and signal](docs/screenshot-toggle.png)

---

## Does this describe your problem?

If you searched for any of these, you're in the right place:

- The modem shows **no signal / 0 bars / "not registered"** on Linux, even
  though it works on Windows.
- **GNOME Settings → Mobile Network is empty**, or there is no mobile data
  toggle at all.
- **ModemManager / `mmcli -L`** lists no modem, or detects the Fibocom but
  cannot connect.
- `lspci` shows `Intel Corporation XMM7360 LTE Advanced Modem`, but nothing
  brings up `wwan0`.
- The in-kernel **`iosm`** driver loads but only creates AT ports that never
  answer.

> **First, the most common false alarm:** an **empty / inactive SIM** (no
> credit, not yet activated) produces *exactly* the "no signal, not registered"
> symptom and sends people down a driver rabbit hole for weeks. Put the SIM in a
> phone and confirm it actually has a working data plan **before** debugging
> drivers. (Ask me how I know.)

---

## Why not just use ModemManager?

The L850's Intel XMM7360 does **not** expose an MBIM/QMI control port that
ModemManager can drive. With the in-kernel `iosm` driver you only get AT ports
plus a proprietary `xmmrpc` port:

- the AT ports stay **silent** — the modem only answers AT once it has been
  initialised and FCC-unlocked over the proprietary RPC channel;
- ModemManager (tested with 1.23.4, Intel plugin) **cannot claim** the `xmmrpc`
  port ("unhandled port type").

So there is no native, ModemManager-based path on this hardware. The
[xmm7360-pci](https://github.com/xmm7360/xmm7360-pci) userspace driver speaks
that proprietary RPC itself and creates a plain `wwan0` network interface. This
project wraps that into a boot service and a desktop toggle.

---

## Requirements

- A Fibocom L850-GL / Intel XMM7360 modem (`lspci -nn | grep 7360`).
- A **working, activated SIM** with a data plan.
- The [xmm7360-pci](https://github.com/xmm7360/xmm7360-pci) driver checked
  out and **built for your running kernel** (see below).
- GNOME Shell **45–48** (Wayland or X11) for the toggle. The helper scripts and
  boot service work without GNOME too.
- `python3`, `iproute2`, `systemd`, `polkit`, `sudo`.

---

## Install

### 1. Build the xmm7360 kernel module

```bash
sudo apt install build-essential "linux-headers-$(uname -r)"   # Debian/Ubuntu
sudo git clone https://github.com/xmm7360/xmm7360-pci /opt/xmm7360-pci
cd /opt/xmm7360-pci && make
```

> ⚠️ **This module is out-of-tree and must be rebuilt after every kernel
> update** (there is no DKMS packaging here). See
> [Kernel updates](#kernel-updates) below.

### 2. Install this project

```bash
git clone https://github.com/michaelruck/fibocom-l850-gnome-lte
cd fibocom-l850-gnome-lte
sudo ./install.sh --xmm7360-dir /opt/xmm7360-pci --build
```

`--build` compiles and installs the kernel module for the current kernel; drop
it if you already did step 1 manually.

### 3. Set your APN and enable the toggle

- Edit `/etc/fibocom-l850-lte/modem.conf` and set `APN=` (see the table below),
  **or** set it later from the extension preferences.
- Log out and back in, then:

```bash
gnome-extensions enable fibocom-l850-lte@michaelruck.github.io
sudo systemctl start fibocom-l850-up.service
```

The **Mobile Data** toggle now appears in the Quick Settings panel.

---

## Common APNs

Most carriers need only the APN (no username/password). Pick yours; when unsure,
search "*\<carrier\> APN*" or ask your provider.

| Country | Carrier            | APN              |
|---------|--------------------|------------------|
| AT      | A1                 | `a1.net`         |
| AT      | Magenta / T-Mobile | `internet.t-mobile` |
| AT      | Drei / Three       | `drei.at`        |
| AT      | Lidl Connect       | `drei.at`        |
| DE      | Telekom            | `internet.telekom` |
| DE      | Vodafone           | `web.vodafone.de` |
| DE      | O2 / Telefónica    | `internet`       |
| FR      | Orange             | `orange`         |
| FR      | Free               | `free`           |
| IT      | TIM                | `ibox.tim.it`    |
| IT      | Vodafone           | `web.omnitel.it` |
| ES      | Movistar           | `movistar.es`    |
| UK      | Three              | `three.co.uk`    |
| UK      | Vodafone           | `internet`       |
| US      | T-Mobile           | `fast.t-mobile.com` |
| US      | AT&T               | `broadband`      |

The operator **name** shown in the toggle comes from
`/etc/fibocom-l850-lte/operators.csv` (PLMN → name). Add a row if your carrier
isn't listed.

---

## How it works

| Piece | Role |
|-------|------|
| `99-fibocom-l850-mm-ignore.rules` | udev rule telling ModemManager to leave this modem alone (see below). |
| `fibocom-l850-up.service` | On boot: waits for the module, runs the bring-up wrapper. |
| `fibocom-l850-up` | Reads `modem.conf`, calls `open_xdatachannel.py` with your APN, registers DNS. |
| `fibocom-l850-ctl on/off/status` | Toggles the `wwan0` link + default route (used by the GNOME toggle). |
| `fibocom-l850-status` | Prints JSON: state, RSRP dBm, EARFCN, RAT, operator, signal bars. |
| `fibocom-l850-apn <apn>` | Rewrites the APN and reconnects (called via `pkexec` from prefs). |
| GNOME extension | Quick Settings toggle + preferences dialog (APN, refresh interval). |

Routing is **Wi-Fi first, LTE as fallback**: the LTE default route uses a higher
metric (1000) than Wi-Fi (typically 600), so it only carries traffic when Wi-Fi
is down. Change `METRIC` in `modem.conf` to taste.

The status helper queries the modem's RPC channel read-only; it is safe to run
while a data session is active.

> **Service note:** `open_xdatachannel.py` deliberately exits with code `1` once
> `wwan0` is up (it only stays resident with `--dbus`). The unit therefore uses
> `Type=oneshot` + `RemainAfterExit=yes` + `SuccessExitStatus=1`, **no
> `Restart=`** — otherwise it loops re-attaching forever.

---

## A phantom "mobile" toggle from ModemManager

Once the xmm7360 driver brings the modem up, its AT ports (`ttyXMM*`) start
answering, and ModemManager will happily adopt the modem and let NetworkManager
show a **second, native mobile-broadband toggle** — often named after your SIM
(e.g. "Lidl"). That toggle cannot actually carry data here (the data path needs
the proprietary xmm7360 RPC channel), so it just competes with this project's
toggle and confuses things.

The installer ships `etc/udev/rules.d/99-fibocom-l850-mm-ignore.rules`, which
sets `ID_MM_DEVICE_IGNORE=1` for the `8086:7360` device so ModemManager leaves
it alone. If you ever see a stray mobile toggle, confirm the rule is installed
and run:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo systemctl restart ModemManager
mmcli -L   # should report "No modems were found"
```

## Kernel updates

After every kernel upgrade, rebuild the module before LTE will work again:

```bash
cd /opt/xmm7360-pci && make clean && make
sudo install -D xmm7360.ko "/lib/modules/$(uname -r)/extra/xmm7360.ko"
sudo depmod -a && sudo modprobe xmm7360
```

(Install `linux-headers-$(uname -r)` for the new kernel first.) If you prefer
automation, set up DKMS for the xmm7360-pci module — that is out of scope here.

---

## Troubleshooting

- **`wwan0` never appears:** is `xmm7360` loaded (`lsmod | grep xmm7360`)? Built
  for *this* kernel? Check `journalctl -u fibocom-l850-up.service -b`.
- **Connected but no internet / DNS fails:** set `DNS=` in `modem.conf` to your
  carrier's resolvers or a public one. Quote multiple servers, since the file is
  sourced by the shell: `DNS="1.1.1.1 9.9.9.9"`.
- **Toggle shows "Disconnected" but you have data:** the `sudo -n` rule may be
  missing — re-run the installer; check `/etc/sudoers.d/fibocom-l850-lte`.
- **Still "not registered":** re-read the SIM warning at the top. Seriously.

---

## Not on extensions.gnome.org

This extension is distributed **only** through this repo (the `install.sh` path
above), not via extensions.gnome.org. For why — it calls privileged helpers and
was built with AI assistance, both of which EGO disallows — see
[docs/PUBLISHING.md](docs/PUBLISHING.md).

## Credits

Built on top of the excellent
[xmm7360-pci](https://github.com/xmm7360/xmm7360-pci) userspace driver. This
project only adds the boot service, helper scripts and GNOME integration.

## License

[GPL-3.0-or-later](LICENSE) — same family as the driver it builds on.
