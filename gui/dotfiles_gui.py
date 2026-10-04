#!/usr/bin/env python3
"""Graphical front end for the dotfiles modules (GTK 4, libadwaita and VTE).

Like the menu of app.sh, it only lists the modules in scripts/ and delegates to them. Every run
happens in an embedded terminal, so sudo passwords, update questions, file choosers and Ctrl+C
behave exactly as in the terminal menu. libadwaita follows the system style (light or dark,
accent color, high contrast); the main menu can also force light or dark.

Start it with ./app.sh --gui, which resolves the update policy and the config mode
(flag > .env > default).
"""

import os
import re
import signal
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    gi.require_version("Vte", "3.91")
    from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango, Vte
except (ImportError, ValueError) as error:
    sys.exit(
        f"The graphical interface needs GTK 4, libadwaita and VTE ({error}).\n"
        "  Fedora: sudo dnf install python3-gobject libadwaita vte291-gtk4\n"
        "  Ubuntu: sudo apt install python3-gi gir1.2-adw-1 gir1.2-vte-3.91"
    )

APP_ID = "local.dotfiles.Setup"
ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT / "scripts"
ICON_FILE = ROOT / "gui" / "dotfiles.svg"
CONFIG_FILE = Path(GLib.get_user_config_dir()) / "dotfiles" / "gui.ini"
LOG_DIR = Path(GLib.get_user_state_dir()) / "dotfiles" / "logs"

# name, label, description (same policies as app.sh: see the update policy in scripts/lib.sh)
POLICIES = [
    ("ask", "Ask", "Shows current -> new and asks before updating what is installed"),
    ("update", "Update", "Updates everything installed that has a newer version"),
    ("keep", "Keep", "Never touches what is installed; only installs what is missing"),
]

COLOR_SCHEMES = {
    "default": Adw.ColorScheme.DEFAULT,
    "light": Adw.ColorScheme.FORCE_LIGHT,
    "dark": Adw.ColorScheme.FORCE_DARK,
}

# GNOME palette for the 16 terminal colors. The light one uses darker tones, so yellow and
# cyan stay readable on a white background.
PALETTE_DARK = [
    "#241f31", "#c01c28", "#2ec27e", "#f5c211", "#1e78e4", "#9841bb", "#0ab9dc", "#c0bfbc",
    "#5e5c64", "#ed333b", "#57e389", "#f8e45c", "#51a1ff", "#c061cb", "#4fd2fd", "#f6f5f4",
]
PALETTE_LIGHT = [
    "#241f31", "#c01c28", "#26a269", "#986a44", "#1c71d8", "#813d9c", "#1a7f95", "#77767b",
    "#5e5c64", "#e01b24", "#2ec27e", "#865e3c", "#3584e4", "#9141ac", "#2190a4", "#9a9996",
]

CSS = """
.module-number {
    font-family: monospace;
    font-feature-settings: "tnum";
    min-width: 2em;
}
.terminal-view vte-terminal {
    padding: 12px;
}
"""


@dataclass
class Module:
    path: Path
    description: str
    category: str

    @property
    def name(self):
        return self.path.name


def discover_modules():
    """Same rules as app.sh: scripts/*.sh except lib.sh, in name order. An empty CATEGORY
    keeps the module in the previous section."""
    modules, category = [], ""
    for path in sorted(SCRIPTS_DIR.glob("*.sh")):
        if path.name == "lib.sh":
            continue
        text = path.read_text(errors="replace")
        desc = re.search(r"^# MENU_DESC:[ \t]*(.*)$", text, re.MULTILINE)
        cat = re.search(r"^# CATEGORY:[ \t]*(.*)$", text, re.MULTILINE)
        if cat and cat.group(1).strip():
            category = cat.group(1).strip()
        description = desc.group(1).strip() if desc else f"Run {path.name}"
        modules.append(Module(path, description, category))
    return modules


def env_file_value(key):
    """A key of .env, read the way app.sh reads it (the file is sourced by bash)."""
    env_file = ROOT / ".env"
    if not env_file.is_file():
        return ""
    result = subprocess.run(
        ["bash", "-c", 'source "$1" > /dev/null 2>&1; printf "%s" "${!2:-}"', "_", str(env_file), key],
        capture_output=True, text=True, check=False,
    )
    return result.stdout.strip()


def initial_config_mode():
    """app.sh --gui passes the resolved mode; started on its own, .env or "full" decide."""
    mode = os.environ.get("DOTFILES_CONFIG_MODE") or env_file_value("CONFIG_MODE")
    return mode if mode in ("full", "missing") else "full"


def initial_policy(config_mode):
    """app.sh --gui passes the resolved policy; started on its own, .env decides, or "keep" in
    the only-missing mode and "ask" otherwise."""
    policy = os.environ.get("DOTFILES_UPDATE_POLICY") or env_file_value("UPDATE_POLICY")
    if policy in [p[0] for p in POLICIES]:
        return policy
    return "keep" if config_mode == "missing" else "ask"


def gnome_detected():
    """Asks lib.sh, so the rule lives in one place (is_gnome)."""
    try:
        result = subprocess.run(
            ["bash", "-c", 'source "$1" > /dev/null 2>&1 && is_gnome', "_", str(SCRIPTS_DIR / "lib.sh")],
            env={**os.environ, "DOTFILES_UPDATE_POLICY": "keep"}, timeout=10, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return True
    return result.returncode == 0


def system_summary():
    name = "Linux"
    try:
        match = re.search(r'^NAME="?([^"\n]*)"?', Path("/etc/os-release").read_text(), re.MULTILINE)
        if match:
            name = match.group(1)
    except OSError:
        pass
    return f"{GLib.get_user_name()}  ·  {GLib.get_host_name()}  ·  {name}"


def monospace_font():
    source = Gio.SettingsSchemaSource.get_default()
    if source and source.lookup("org.gnome.desktop.interface", True):
        return Gio.Settings(schema_id="org.gnome.desktop.interface").get_string("monospace-font-name")
    return "Monospace 11"


def home_relative(path):
    home = str(Path.home())
    text = str(path)
    return "~" + text[len(home):] if text.startswith(home + "/") else text


def load_setting(key, default):
    keyfile = GLib.KeyFile()
    try:
        keyfile.load_from_file(str(CONFIG_FILE), GLib.KeyFileFlags.NONE)
        return keyfile.get_string("gui", key)
    except GLib.Error:
        return default


def save_setting(key, value):
    keyfile = GLib.KeyFile()
    try:
        keyfile.load_from_file(str(CONFIG_FILE), GLib.KeyFileFlags.KEEP_COMMENTS)
    except GLib.Error:
        pass
    keyfile.set_string("gui", key, value)
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    keyfile.save_to_file(str(CONFIG_FILE))


def desktop_exec_arg(path):
    """Quotes a path for the Exec key (Desktop Entry spec: quoting rule, then string escapes)."""
    quoted = str(path)
    for char in '\\"`$':
        quoted = quoted.replace(char, "\\" + char)
    return '"' + quoted.replace("\\", "\\\\").replace("%", "%%") + '"'


def exit_code(wait_status):
    if os.WIFEXITED(wait_status):
        return os.WEXITSTATUS(wait_status)
    if os.WIFSIGNALED(wait_status):
        return 128 + os.WTERMSIG(wait_status)
    return 1


class SetupWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Dotfiles", default_width=900, default_height=780)
        self.set_size_request(360, 480)
        self.modules = discover_modules()
        self.config_mode = initial_config_mode()
        self.policy = initial_policy(self.config_mode)
        self.running = False

        self.toasts = Adw.ToastOverlay()
        self.nav = Adw.NavigationView()
        self.toasts.set_child(self.nav)
        self.set_content(self.toasts)

        self.nav.add(self._build_modules_page())
        self.run_page = self._build_run_page()
        self.nav.add(self.run_page)

        style = Adw.StyleManager.get_default()
        style.connect("notify::dark", lambda *_: self._apply_terminal_colors())
        self._apply_terminal_colors()
        self.connect("close-request", self._on_close_request)

    # ─── Modules page ─────────────────────────────────────────────────────────

    def _build_modules_page(self):
        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle(title="Dotfiles", subtitle=system_summary()))
        header.pack_end(self._build_menu_button())

        page = Adw.PreferencesPage()
        page.add(self._build_overview_group())

        # Consecutive modules of the same category share a group, as in the menu
        group, category = None, None
        for index, module in enumerate(self.modules, start=1):
            if group is None or module.category != category:
                category = module.category
                group = Adw.PreferencesGroup(title=category.capitalize() or "Modules")
                page.add(group)
            group.add(self._build_module_row(index, module))

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        if not gnome_detected():
            desktop = os.environ.get("XDG_CURRENT_DESKTOP") or "unknown"
            toolbar.add_top_bar(Adw.Banner(
                title=f"GNOME not detected (desktop: {desktop}). GNOME steps will be skipped.", revealed=True,
            ))
        toolbar.set_content(page)
        return Adw.NavigationPage(title="Dotfiles", tag="modules", child=toolbar)

    def _build_overview_group(self):
        group = Adw.PreferencesGroup()

        policy_row = Adw.ComboRow(use_markup=False, use_subtitle=False)
        policy_row.set_title("Updates")
        policy_row.set_model(Gtk.StringList.new([label for _, label, _ in POLICIES]))
        names = [name for name, _, _ in POLICIES]
        policy_row.set_selected(names.index(self.policy))
        policy_row.set_subtitle(POLICIES[policy_row.get_selected()][2])

        def on_policy(row, _param):
            self.policy = names[row.get_selected()]
            row.set_subtitle(POLICIES[row.get_selected()][2])

        policy_row.connect("notify::selected", on_policy)

        missing_row = Adw.SwitchRow(use_markup=False, active=self.config_mode == "missing")
        missing_row.set_title("Only What Is Missing")
        missing_row.set_subtitle("For a system already set up: installs and configures only what is "
                                 "missing, removes nothing and keeps every setting you have")

        def on_missing(row, _param):
            self.config_mode = "missing" if row.get_active() else "full"
            if row.get_active():
                # Completing a system is not updating it (same default as --only-missing)
                policy_row.set_selected(names.index("keep"))

        missing_row.connect("notify::active", on_missing)
        group.add(missing_row)
        group.add(policy_row)

        # use_markup=False before any text: descriptions may contain "&" (GRUB & Plymouth)
        run_all = Adw.ActionRow(use_markup=False)
        run_all.set_title("Run every module")
        run_all.set_subtitle(f"In order, like ./app.sh --all: sudo password once, log in {home_relative(LOG_DIR)}")
        button = Gtk.Button(label="Run All", valign=Gtk.Align.CENTER, css_classes=["suggested-action"])
        button.connect("clicked", lambda *_: self._confirm_run_all())
        run_all.add_suffix(button)
        run_all.set_activatable_widget(button)
        group.add(run_all)

        self.env_row = Adw.ActionRow(use_markup=False)
        self.env_row.set_title("Personal settings (.env)")
        self.env_button = Gtk.Button(valign=Gtk.Align.CENTER)
        self.env_button.connect("clicked", lambda *_: self._open_env())
        self.env_row.add_suffix(self.env_button)
        self.env_row.set_activatable_widget(self.env_button)
        self._update_env_row()
        group.add(self.env_row)
        return group

    def _build_module_row(self, index, module):
        row = Adw.ActionRow(use_markup=False, activatable=True)
        row.set_title(module.description)
        row.set_subtitle(module.name)
        row.add_prefix(Gtk.Label(label=f"{index:02d}", css_classes=["module-number", "dim-label"]))
        icon = Gtk.Image(icon_name="media-playback-start-symbolic", tooltip_text="Run")
        row.add_suffix(icon)
        row.connect("activated", lambda *_: self._confirm_run_module(module))
        return row

    def _build_menu_button(self):
        menu = Gio.Menu()
        theme = Gio.MenuItem()
        theme.set_attribute_value("custom", GLib.Variant.new_string("theme"))
        section = Gio.Menu()
        section.append_item(theme)
        menu.append_section(None, section)
        actions = Gio.Menu()
        actions.append("Add to Applications Menu", "app.install-desktop")
        actions.append("Open Logs Folder", "app.open-logs")
        menu.append_section(None, actions)
        quit_section = Gio.Menu()
        quit_section.append("Quit", "app.quit")
        menu.append_section(None, quit_section)

        toggles = Adw.ToggleGroup(margin_start=12, margin_end=12, margin_top=6, margin_bottom=6, hexpand=True)
        for name, label, tooltip in [
            ("default", "System", "Follow the system style"),
            ("light", "Light", "Always light"),
            ("dark", "Dark", "Always dark"),
        ]:
            toggles.add(Adw.Toggle(name=name, label=label, tooltip=tooltip))
        toggles.set_active_name(self.get_application().color_scheme)
        toggles.connect("notify::active-name", lambda group, _: self.get_application().set_color_scheme(group.get_active_name()))

        popover = Gtk.PopoverMenu.new_from_model(menu)
        popover.add_child(toggles, "theme")
        return Gtk.MenuButton(icon_name="open-menu-symbolic", popover=popover, primary=True, tooltip_text="Main Menu")

    # ─── .env ─────────────────────────────────────────────────────────────────

    def _update_env_row(self):
        if (ROOT / ".env").is_file():
            self.env_row.set_subtitle("Read by the modules instead of asking (git identity, GitHub user, images...)")
            self.env_button.set_label("Edit")
        else:
            self.env_row.set_subtitle("Not created yet: modules 01, 07 and 12 ask in the terminal")
            self.env_button.set_label("Create")

    def _open_env(self):
        env_file = ROOT / ".env"
        if not env_file.exists():
            env_file.write_text((ROOT / ".env.example").read_text())
            self._update_env_row()
            self.toast(".env created from .env.example")
        Gtk.FileLauncher.new(Gio.File.new_for_path(str(env_file))).launch(self, None, None, None)

    # ─── Run page ─────────────────────────────────────────────────────────────

    def _build_run_page(self):
        self.run_title = Adw.WindowTitle()
        header = Adw.HeaderBar()
        header.set_title_widget(self.run_title)
        self.stop_button = Gtk.Button(label="Stop", css_classes=["destructive-action"],
                                      tooltip_text="Send Ctrl+C to the running module")
        self.stop_button.connect("clicked", lambda *_: self.terminal.feed_child(b"\x03"))
        header.pack_end(self.stop_button)

        self.terminal = Vte.Terminal(vexpand=True, hexpand=True)
        self.terminal.set_scrollback_lines(10000)
        self.terminal.set_mouse_autohide(True)
        self.terminal.set_font(Pango.FontDescription.from_string(monospace_font()))
        self.terminal.connect("child-exited", self._on_child_exited)
        shortcuts = Gtk.ShortcutController()
        shortcuts.add_shortcut(Gtk.Shortcut.new(
            Gtk.ShortcutTrigger.parse_string("<Control><Shift>c"),
            Gtk.CallbackAction.new(lambda *_: self.terminal.copy_clipboard_format(Vte.Format.TEXT) or True),
        ))
        shortcuts.add_shortcut(Gtk.Shortcut.new(
            Gtk.ShortcutTrigger.parse_string("<Control><Shift>v"),
            Gtk.CallbackAction.new(lambda *_: self.terminal.paste_clipboard() or True),
        ))
        self.terminal.add_controller(shortcuts)
        # The terminal paints no background of its own: the "view" style behind it does, so it
        # always matches the light or dark style
        scrolled = Gtk.ScrolledWindow(child=self.terminal, css_classes=["view", "terminal-view"])

        self.spinner = Adw.Spinner()
        self.status_icon = Gtk.Image()
        self.status_label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.back_button = Gtk.Button(label="Back to Modules", css_classes=["suggested-action"])
        self.back_button.connect("clicked", lambda *_: self.nav.pop())
        status = Gtk.Box(spacing=8, margin_start=6)
        status.append(self.spinner)
        status.append(self.status_icon)
        status.append(self.status_label)
        bar = Gtk.ActionBar()
        bar.pack_start(status)
        bar.pack_end(self.back_button)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(scrolled)
        toolbar.add_bottom_bar(bar)
        return Adw.NavigationPage(title="Run", tag="run", child=toolbar)

    def _apply_terminal_colors(self):
        dark = Adw.StyleManager.get_default().get_dark()

        def rgba(spec):
            color = Gdk.RGBA()
            color.parse(spec)
            return color

        foreground = rgba("#ffffff" if dark else "rgba(0, 0, 0, 0.8)")
        palette = [rgba(c) for c in (PALETTE_DARK if dark else PALETTE_LIGHT)]
        self.terminal.set_colors(foreground, rgba("rgba(0, 0, 0, 0)"), palette)

    def _set_status(self, state, text):
        self.spinner.set_visible(state == "running")
        self.status_icon.set_visible(state != "running")
        icons = {"done": ("object-select-symbolic", "success"),
                 "stopped": ("dialog-warning-symbolic", "warning"),
                 "failed": ("dialog-error-symbolic", "error")}
        if state in icons:
            name, css = icons[state]
            self.status_icon.set_from_icon_name(name)
            self.status_icon.set_css_classes([css])
            self.status_label.set_css_classes([css])
        else:
            self.status_label.set_css_classes([])
        self.status_label.set_label(text)

    def run(self, title, subtitle, argv):
        self.running = True
        self.run_title.set_title(title)
        self.run_title.set_subtitle(subtitle)
        self.terminal.reset(True, True)
        self._set_status("running", "Running. Type in the terminal when a module asks for something.")
        self.stop_button.set_visible(True)
        self.back_button.set_visible(False)
        self.run_page.set_can_pop(False)
        self.nav.push(self.run_page)

        env = {**os.environ, "DOTFILES_UPDATE_POLICY": self.policy, "DOTFILES_CONFIG_MODE": self.config_mode}
        self.terminal.spawn_async(
            Vte.PtyFlags.DEFAULT, str(ROOT), argv, [f"{k}={v}" for k, v in env.items()],
            GLib.SpawnFlags.DEFAULT, None, None, -1, None, self._on_spawned, None,
        )
        self.terminal.grab_focus()

    def _on_spawned(self, _terminal, pid, error, _data=None):
        if pid == -1 or error is not None:
            self._finish("failed", f"Could not start: {error.message if error else 'unknown error'}")

    def _on_child_exited(self, _terminal, wait_status):
        code = exit_code(wait_status)
        if code == 0:
            self._finish("done", "Done.")
        elif code == 128 + signal.SIGINT:
            self._finish("stopped", "Stopped (Ctrl+C).")
        else:
            self._finish("failed", f"Exited with errors (status {code}). The output above shows where.")

    def _finish(self, state, text):
        self.running = False
        self._set_status(state, text)
        self.stop_button.set_visible(False)
        self.back_button.set_visible(True)
        self.run_page.set_can_pop(True)
        self.back_button.grab_focus()
        if not self.is_active():
            notification = Gio.Notification.new(self.run_title.get_title())
            notification.set_body(text)
            self.get_application().send_notification("run-finished", notification)

    # ─── Confirmations ────────────────────────────────────────────────────────

    def _policy_description(self):
        return next(description for name, _, description in POLICIES if name == self.policy)

    def _settings_summary(self):
        mode = ("Only what is missing: nothing is removed and your settings are kept."
                if self.config_mode == "missing" else "Full: applies the repository configuration.")
        return f"{mode}\nUpdates: {self._policy_description().lower()}."

    def _run_subtitle(self, name):
        mode = "only missing" if self.config_mode == "missing" else "full"
        return f"{name}  ·  {mode}  ·  {self.policy}"

    def _confirm(self, heading, body, response_label, on_confirm):
        dialog = Adw.AlertDialog(heading=heading, body=body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("run", response_label)
        dialog.set_response_appearance("run", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("run")
        dialog.set_close_response("cancel")
        dialog.connect("response", lambda _d, response: response == "run" and on_confirm())
        dialog.present(self)

    def _confirm_run_module(self, module):
        self._confirm(
            module.description,
            f"{module.name} may install, remove or change software and ask for your sudo "
            f"password in the terminal.\n\n{self._settings_summary()}",
            "Run",
            lambda: self.run(module.description, self._run_subtitle(module.name), ["bash", str(module.path)]),
        )

    def _confirm_run_all(self):
        self._confirm(
            "Run every module?",
            f"The {len(self.modules)} modules run in order. The sudo password is asked once, a failing "
            f"module does not stop the next ones, and the run is logged in {home_relative(LOG_DIR)}."
            f"\n\n{self._settings_summary()}",
            "Run All",
            lambda: self.run("Every module", self._run_subtitle("./app.sh --all"),
                             [str(ROOT / "app.sh"), "--all", f"--{self.policy}",
                              "--only-missing" if self.config_mode == "missing" else "--full"]),
        )

    def _on_close_request(self, _window):
        if not self.running:
            return False
        dialog = Adw.AlertDialog(
            heading="A module is still running",
            body="Closing the window stops it, like closing a terminal in the middle of a run.",
        )
        dialog.add_response("cancel", "Keep Running")
        dialog.add_response("close", "Stop and Close")
        dialog.set_response_appearance("close", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_close_response("cancel")

        def on_response(_dialog, response):
            if response == "close":
                self.running = False
                # After the dialog is gone: while it is open, closing the window closes the dialog
                GLib.idle_add(self.close)

        dialog.connect("response", on_response)
        dialog.present(self)
        return True

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast(title=text))


class SetupApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.color_scheme = "default"

    def do_startup(self):
        Adw.Application.do_startup(self)
        css = Gtk.CssProvider()
        css.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        saved = load_setting("color-scheme", "default")
        self.color_scheme = saved if saved in COLOR_SCHEMES else "default"
        Adw.StyleManager.get_default().set_color_scheme(COLOR_SCHEMES[self.color_scheme])

        for name, callback in [("install-desktop", self._install_desktop_entry),
                               ("open-logs", self._open_logs),
                               ("quit", self._quit)]:
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", callback)
            self.add_action(action)
        self.set_accels_for_action("app.quit", ["<Control>q"])

    def do_activate(self):
        window = self.props.active_window or SetupWindow(self)
        window.present()

    def set_color_scheme(self, name):
        if name not in COLOR_SCHEMES:
            return
        self.color_scheme = name
        Adw.StyleManager.get_default().set_color_scheme(COLOR_SCHEMES[name])
        save_setting("color-scheme", name)

    def _install_desktop_entry(self, *_):
        path = Path(GLib.get_user_data_dir()) / "applications" / f"{APP_ID}.desktop"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Dotfiles Setup\n"
            "Comment=Run the dotfiles automation modules\n"
            f"Exec={desktop_exec_arg(ROOT / 'app.sh')} --gui\n"
            f"Icon={ICON_FILE}\n"
            "Terminal=false\n"
            "Categories=System;Settings;\n"
            "StartupNotify=true\n"
        )
        self.props.active_window.toast("Added to the applications menu")

    def _open_logs(self, *_):
        window = self.props.active_window
        if not LOG_DIR.is_dir():
            window.toast("No logs yet: Run All creates one per run")
            return
        Gtk.FileLauncher.new(Gio.File.new_for_path(str(LOG_DIR))).launch(window, None, None, None)

    def _quit(self, *_):
        # Through close-request, so a running module is not dropped without asking
        window = self.props.active_window
        if window:
            window.close()


def main():
    if os.geteuid() == 0:
        sys.exit("Do not run this as root or with sudo. Use your normal user.")
    # PyGObject already tried to open the display on import (and its Gtk.init_check() reports
    # True even when that failed), so ask GDK
    if Gdk.Display.get_default() is None:
        sys.exit("No graphical display found. Run it inside the desktop session, or use ./app.sh for the terminal menu.")
    return SetupApp().run(sys.argv[:1])


if __name__ == "__main__":
    sys.exit(main())
