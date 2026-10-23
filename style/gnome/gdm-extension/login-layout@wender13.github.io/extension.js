// Login screen layout (GDM only, "session-modes": ["gdm"]).
//
// While the user list shows, it moves to the left half of the primary monitor, a solid box
// with the time and date takes the right half and the panel clock is hidden. Once a user is
// picked, the password step is left exactly as GNOME draws it.
//
// GNOME Shell has no layout settings for the login screen, so this relies on internals of its
// login dialog (Main.screenShield._dialog._userSelectionBox, the same in GNOME 48 to 50). When
// they are missing, the extension does nothing and the default login screen stays.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GnomeDesktop from 'gi://GnomeDesktop';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {formatDateWithCFormatString} from 'resource:///org/gnome/shell/misc/dateUtils.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class LoginLayoutExtension extends Extension {
    enable() {
        this._interface = new Gio.Settings({schema_id: 'org.gnome.desktop.interface'});
        // The login dialog is created when the shell starts up, after extensions load
        if (Main.screenShield?._dialog)
            this._attach();
        else
            this._startupId = Main.layoutManager.connect('startup-complete', () => this._attach());
    }

    disable() {
        if (this._startupId) {
            Main.layoutManager.disconnect(this._startupId);
            this._startupId = 0;
        }
        this._detach();
        this._interface = null;
    }

    _attach() {
        const dialog = Main.screenShield?._dialog;
        const userBox = dialog?._userSelectionBox;
        if (!userBox || this._box)
            return;
        this._userBox = userBox;

        this._box = new St.BoxLayout({
            style_class: 'dotfiles-login-clock',
            orientation: Clutter.Orientation.VERTICAL,
        });
        this._time = new St.Label({style_class: 'dotfiles-login-clock-time', x_align: Clutter.ActorAlign.CENTER});
        this._date = new St.Label({style_class: 'dotfiles-login-clock-date', x_align: Clutter.ActorAlign.CENTER});
        this._box.add_child(this._time);
        this._box.add_child(this._date);
        dialog.get_parent().add_child(this._box);
        // The shell destroys the dialog and the box with it when the session starts: forget them
        this._box.connect('destroy', () => {
            this._box = null;
            this._userBox = null;
            this._clock = null;
        });

        // Ticks every second when the seconds are shown, otherwise every minute. Every signal
        // is tied to the box (connectObject), so it is disconnected when the box goes away.
        this._clock = new GnomeDesktop.WallClock();
        this._clock.connectObject('notify::clock', () => this._update(), this._box);
        Main.layoutManager.connectObject('monitors-changed', () => this._place(), this._box);
        userBox.connectObject('notify::visible', () => this._sync(), this._box);
        this._update();
        this._sync();
    }

    _detach() {
        if (!this._box)
            return;
        this._userBox.translation_x = 0;
        this._box.destroy();
        this._setPanelClockVisible(true);
    }

    _update() {
        const now = GLib.DateTime.new_now_local();
        const seconds = this._interface.get_boolean('clock-show-seconds');
        let format;
        if (this._interface.get_string('clock-format') === '24h')
            format = seconds ? '%H:%M:%S' : '%H:%M';
        else
            format = seconds ? '%l:%M:%S %p' : '%l:%M %p';
        this._time.text = now.format(format).trim();
        // The date format GNOME Shell's own clock uses, in the system language
        this._date.text = formatDateWithCFormatString(new Date(),
            Shell.util_translate_time_string('%A %B %e %Y')).replace(/\s+/g, ' ').trim();
        this._place();
    }

    // The user list centered on the left half, the box on the right half of the primary monitor
    _place() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !this._box)
            return;
        this._userBox.translation_x = -Math.floor(monitor.width / 4);
        const [, , width, height] = this._box.get_preferred_size();
        this._box.set_position(
            monitor.x + Math.floor(monitor.width * 3 / 4 - width / 2),
            monitor.y + Math.floor((monitor.height - height) / 2));
    }

    // The new layout only while the user list shows; the password step stays standard
    _sync() {
        const list = this._userBox.visible;
        this._box.visible = list;
        this._setPanelClockVisible(!list);
    }

    _setPanelClockVisible(visible) {
        const dateMenu = Main.panel.statusArea.dateMenu;
        if (dateMenu)
            dateMenu.container.visible = visible;
    }
}
