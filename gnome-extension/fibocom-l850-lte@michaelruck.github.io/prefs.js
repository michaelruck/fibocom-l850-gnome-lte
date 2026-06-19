// Preferences for the Fibocom L850 LTE Toggle extension.
//
// Lets the user view/change the APN (applied via pkexec + the fibocom-l850-apn
// helper) and tune the status poll interval. The APN itself is stored in
// /etc/fibocom-l850-lte/modem.conf, not in gsettings — this dialog only reads
// it for display and writes it through the privileged helper.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {ExtensionPreferences} from 'resource:///org/gnome/shell/extensions/prefs.js';

const CONF = '/etc/fibocom-l850-lte/modem.conf';
const APN_HELPER = '/usr/local/bin/fibocom-l850-apn';
const PKEXEC = '/usr/bin/pkexec';
const APN_RE = /^[A-Za-z0-9._-]+$/;

function readApn() {
    try {
        const [ok, bytes] = GLib.file_get_contents(CONF);
        if (!ok)
            return '';
        const text = new TextDecoder().decode(bytes);
        for (const line of text.split('\n')) {
            const m = line.match(/^\s*APN=(.*)$/);
            if (m)
                return m[1].trim().replace(/^["']|["']$/g, '');
        }
    } catch (e) {
        // config not readable -> leave blank
    }
    return '';
}

export default class FibocomLtePrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        const page = new Adw.PreferencesPage({
            title: 'Settings',
            icon_name: 'network-cellular-symbolic',
        });
        window.add(page);

        // --- APN group -----------------------------------------------------
        const apnGroup = new Adw.PreferencesGroup({
            title: 'Access Point Name (APN)',
            description: 'The APN your carrier requires for mobile data. ' +
                'Applying it asks for your password and reconnects the modem.',
        });
        page.add(apnGroup);

        const apnRow = new Adw.EntryRow({title: 'APN'});
        apnRow.set_text(readApn());
        apnGroup.add(apnRow);

        const statusRow = new Adw.ActionRow({title: ' '});
        const applyBtn = new Gtk.Button({
            label: 'Apply',
            valign: Gtk.Align.CENTER,
            css_classes: ['suggested-action'],
        });
        statusRow.add_suffix(applyBtn);
        apnGroup.add(statusRow);

        const setStatus = (text) => statusRow.set_title(text);

        applyBtn.connect('clicked', () => {
            const apn = apnRow.get_text().trim();
            if (!APN_RE.test(apn)) {
                setStatus('Invalid APN — use letters, digits, dot, dash, underscore.');
                return;
            }
            applyBtn.set_sensitive(false);
            setStatus('Applying… (a password prompt may appear)');
            try {
                const proc = Gio.Subprocess.new(
                    [PKEXEC, APN_HELPER, apn],
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE
                );
                proc.communicate_utf8_async(null, null, (p, res) => {
                    applyBtn.set_sensitive(true);
                    let ok = false;
                    try { ok = p.communicate_utf8_finish(res) && p.get_successful(); }
                    catch (e) { ok = false; }
                    setStatus(ok
                        ? `APN set to “${apn}”. Reconnecting…`
                        : 'Could not set APN (cancelled or failed).');
                });
            } catch (e) {
                applyBtn.set_sensitive(true);
                setStatus(`Error: ${e.message}`);
            }
        });

        // --- Behaviour group ----------------------------------------------
        const behGroup = new Adw.PreferencesGroup({title: 'Behaviour'});
        page.add(behGroup);

        const pollRow = new Adw.SpinRow({
            title: 'Status refresh interval',
            subtitle: 'How often to poll signal/operator (seconds)',
            adjustment: new Gtk.Adjustment({
                lower: 3, upper: 120, step_increment: 1, page_increment: 5,
            }),
        });
        behGroup.add(pollRow);
        settings.bind('poll-seconds', pollRow, 'value', Gio.SettingsBindFlags.DEFAULT);
    }
}
