// Fibocom L850 LTE Toggle — GNOME Shell Quick Settings extension.
//
// Adds a "Mobile Data" toggle that drives the wwan0 interface via the helper
// scripts (fibocom-l850-ctl / fibocom-l850-status) shipped with
// fibocom-l850-gnome-lte. The toggle shows connection state, signal strength,
// operator and RAT.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {QuickToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const CTL = '/usr/local/bin/fibocom-l850-ctl';
const STATUS = '/usr/local/bin/fibocom-l850-status';
const SUDO = '/usr/bin/sudo';
const DEFAULT_POLL_SECONDS = 10;

const ICON_BY_BARS = [
    'network-cellular-signal-none-symbolic',       // 0
    'network-cellular-signal-weak-symbolic',       // 1
    'network-cellular-signal-ok-symbolic',         // 2
    'network-cellular-signal-good-symbolic',       // 3
    'network-cellular-signal-excellent-symbolic',  // 4
];
const ICON_OFF = 'network-cellular-offline-symbolic';

const LteToggle = GObject.registerClass(
class LteToggle extends QuickToggle {
    _init(settings) {
        super._init({
            title: 'Mobile Data',
            iconName: ICON_OFF,
            toggleMode: true,
        });
        this._settings = settings;
        this._setSubtitle('…');

        this.connect('clicked', () => this._setState(this.checked));

        this._subtitleOk = true;
        this._busy = false;
        this._sync();

        const poll = this._settings
            ? Math.max(3, this._settings.get_int('poll-seconds'))
            : DEFAULT_POLL_SECONDS;
        this._timeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, poll, () => {
            this._sync();
            return GLib.SOURCE_CONTINUE;
        });
    }

    // The subtitle property only exists on newer shells -> never hard-depend.
    _setSubtitle(text) {
        if (!this._subtitleOk)
            return;
        try {
            this.set({subtitle: text});
        } catch (e) {
            this._subtitleOk = false;
        }
    }

    _setState(on) {
        try {
            const proc = Gio.Subprocess.new(
                [SUDO, '-n', CTL, on ? 'on' : 'off'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE
            );
            this._setSubtitle(on ? 'connecting…' : 'disconnecting…');
            proc.communicate_utf8_async(null, null, (p, res) => {
                try { p.communicate_utf8_finish(res); } catch (e) { logError(e); }
                this._sync();
            });
        } catch (e) {
            logError(e);
        }
    }

    _sync() {
        if (this._busy)
            return;
        this._busy = true;
        try {
            const proc = Gio.Subprocess.new(
                [SUDO, '-n', STATUS],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE
            );
            proc.communicate_utf8_async(null, null, (p, res) => {
                this._busy = false;
                let data = {};
                try {
                    const [, stdout] = p.communicate_utf8_finish(res);
                    data = JSON.parse((stdout || '').trim());
                } catch (e) {
                    return;
                }
                this._apply(data);
            });
        } catch (e) {
            this._busy = false;
        }
    }

    _apply(d) {
        const connected = d.state === 'connected';
        if (this.checked !== connected)
            this.set({checked: connected});

        if (connected) {
            const bars = Math.max(0, Math.min(4, d.bars ?? 0));
            this.set({iconName: ICON_BY_BARS[bars]});
            const parts = [];
            if (d.operator) parts.push(d.operator);
            if (d.rat) parts.push(d.rat);
            if (typeof d.rsrp_dbm === 'number') parts.push(`${d.rsrp_dbm} dBm`);
            this._setSubtitle(parts.join(' · ') || 'Connected');
        } else if (d.state === 'off') {
            this.set({iconName: ICON_OFF});
            this._setSubtitle('Off');
        } else if (d.state === 'absent') {
            this.set({iconName: ICON_OFF});
            this._setSubtitle('Modem off');
        } else {
            this.set({iconName: ICON_OFF});
            this._setSubtitle('Disconnected');
        }
    }

    destroy() {
        if (this._timeout) {
            GLib.source_remove(this._timeout);
            this._timeout = null;
        }
        super.destroy();
    }
});

const LteIndicator = GObject.registerClass(
class LteIndicator extends SystemIndicator {
    _init(settings) {
        super._init();
        this._toggle = new LteToggle(settings);
        this.quickSettingsItems.push(this._toggle);
    }

    destroy() {
        this._toggle.destroy();
        super.destroy();
    }
});

export default class FibocomLteExtension extends Extension {
    enable() {
        let settings = null;
        try { settings = this.getSettings(); } catch (e) { settings = null; }
        this._indicator = new LteIndicator(settings);
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
