// Login screen layout (GDM only, "session-modes": ["gdm"]).
//
// While the user list shows, the time and date take part of the primary monitor, the user
// list moves out of their way and the panel clock is hidden. Once a user is picked, the
// password step is left exactly as GNOME draws it. The layout, and whether the panel is glass
// (blurring what is behind it) or solid, come from this extension's settings, which
// scripts/16-loginLayout.sh sets in GDM's dconf database.
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

// kind: what holds the time and date; side: which way it goes (1 right or bottom, -1 left or top)
const LAYOUTS = {
    'panel-right': {kind: 'panel', side: 1},
    'panel-left': {kind: 'panel', side: -1},
    'card-right': {kind: 'card', side: 1},
    'card-left': {kind: 'card', side: -1},
    'band-bottom': {kind: 'band', side: 1},
    'band-top': {kind: 'band', side: -1},
    'clock-below': {kind: 'plain', side: 1},
    'clock-above': {kind: 'plain', side: -1},
};

// The login screen background (#lockDialogGroup), darkened for the solid panel
const BACKGROUND = [0x22, 0x22, 0x26];

// Clock above or below the user list: where the middle of the clock and the user list go, as
// fractions of the screen height. Proportions instead of gaps from the middle, because the
// user list is not exactly centered (the "Not listed?" link counts in its height).
const PLAIN_ABOVE = {clock: 0.34, user: 0.60};
const PLAIN_BELOW = {clock: 0.66, user: 0.40};

export default class LoginLayoutExtension extends Extension {
    enable() {
        this._interface = new Gio.Settings({schema_id: 'org.gnome.desktop.interface'});
        this._settings = this.getSettings();
        this._settingsId = this._settings.connect('changed', () => {
            this._detach();
            this._attach();
        });
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
        this._settings.disconnect(this._settingsId);
        this._detach();
        this._settings = null;
        this._interface = null;
    }

    _attach() {
        const dialog = Main.screenShield?._dialog;
        const userBox = dialog?._userSelectionBox;
        if (!userBox || this._box)
            return;
        this._userBox = userBox;
        this._layout = LAYOUTS[this._settings.get_string('layout')] ?? LAYOUTS['panel-right'];
        const {kind} = this._layout;

        // The time and date, centered in whatever holds them
        const content = new St.BoxLayout({
            style_class: 'dotfiles-login-clock-content',
            orientation: Clutter.Orientation.VERTICAL,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._time = new St.Label({style_class: 'dotfiles-login-clock-time', x_align: Clutter.ActorAlign.CENTER});
        this._date = new St.Label({style_class: 'dotfiles-login-clock-date', x_align: Clutter.ActorAlign.CENTER});
        content.add_child(this._time);
        content.add_child(this._date);
        this._box = new St.Bin({style_class: `dotfiles-login-clock dotfiles-login-clock-${kind}`, child: content});
        if (kind !== 'plain')
            this._styleBackground();
        // Behind the dialog, so its buttons (accessibility, bottom right) stay on top and usable
        dialog.get_parent().insert_child_below(this._box, dialog);
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
        this._place();
        this._sync();
    }

    _detach() {
        if (!this._box)
            return;
        this._userBox.translation_x = 0;
        this._userBox.translation_y = 0;
        this._box.destroy();
        this._setPanelClockVisible(true);
    }

    // Glass: the background behind the panel blurred, under a black tint. Solid: the login
    // screen background color, darkened.
    _styleBackground() {
        const darkness = this._settings.get_int('panel-darkness') / 100;
        if (this._settings.get_string('panel-style') === 'glass') {
            this._box.set_style(`background-color: rgba(0, 0, 0, ${darkness});`);
            const radius = this._settings.get_int('panel-blur');
            if (radius > 0) {
                this._box.add_effect_with_name('dotfiles-blur', new Shell.BlurEffect({
                    mode: Shell.BlurMode.BACKGROUND,
                    radius,
                    brightness: 1.0,
                }));
            }
        } else {
            const [r, g, b] = BACKGROUND.map(c => Math.round(c * (1 - darkness)));
            this._box.set_style(`background-color: rgb(${r}, ${g}, ${b});`);
        }
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
        // The card and the plain clock follow the size of the text
        if (this._layout.kind === 'card' || this._layout.kind === 'plain')
            this._place();
    }

    // Positions on the primary monitor: the user list moves with translations (the dialog
    // still allocates it), the box is placed and sized directly
    _place() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !this._box)
            return;
        const {x, y, width, height} = monitor;
        const {kind, side} = this._layout;
        let userX = 0, userY = 0;

        if (kind === 'panel') {
            // Half the screen, top to bottom; the user list centered on the other half
            const half = Math.floor(width / 2);
            userX = -side * Math.floor(width / 4);
            this._box.set_position(side > 0 ? x + half : x, y);
            this._box.set_size(side > 0 ? width - half : half, height);
        } else if (kind === 'band') {
            // A third of the screen, full width; the user list centered on the rest
            const third = Math.floor(height / 3);
            userY = -side * Math.floor(height / 6);
            this._box.set_position(x, side > 0 ? y + height - third : y);
            this._box.set_size(width, third);
        } else {
            this._box.set_size(-1, -1);
            const [, , boxWidth, boxHeight] = this._box.get_preferred_size();
            if (kind === 'card') {
                // Centered on one half; the user list centered on the other half
                userX = -side * Math.floor(width / 4);
                this._box.set_position(
                    x + Math.floor(width / 2 + side * width / 4 - boxWidth / 2),
                    y + Math.floor((height - boxHeight) / 2));
            } else {
                // Above or below the user list, at fixed proportions of the screen height
                const place = side > 0 ? PLAIN_BELOW : PLAIN_ABOVE;
                userY = Math.floor(height * (place.user - 0.5));
                this._box.set_position(x + Math.floor((width - boxWidth) / 2),
                    y + Math.floor(height * place.clock - boxHeight / 2));
            }
        }
        this._userBox.translation_x = userX;
        this._userBox.translation_y = userY;
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
