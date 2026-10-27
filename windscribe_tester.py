import tkinter as tk
from tkinter import ttk, messagebox
import json
import plistlib
import subprocess
import threading
import time
import re
import os
import shutil

# windscribe-cli locations prints JSON log lines and no server list while the
# desktop app is running. Datacenters live in the app settings. Connect with
# the nickname.
IS_WINDOWS = os.name == "nt"
MAC_INVENTORY_PLIST = os.path.expanduser(
    "~/Library/Preferences/com.windscribe.Windscribe2.plist"
)
WINDOWS_SETTINGS_KEY = r"Software\Windscribe\Windscribe2"


def subprocess_kwargs():
    """Keep CLI and ping from opening a console window on Windows."""
    if IS_WINDOWS:
        return {"creationflags": subprocess.CREATE_NO_WINDOW}
    return {}


def read_wsnet_settings():
    """JSON blob that contains invLocations."""
    if IS_WINDOWS:
        return _read_wsnet_settings_windows()
    with open(MAC_INVENTORY_PLIST, "rb") as f:
        root = plistlib.load(f)
    value = root["wsnetSettings"]
    if isinstance(value, bytes):
        value = value.decode("utf-8")
    return value


def _read_wsnet_settings_windows():
    import winreg

    last_error = None
    for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        try:
            with winreg.OpenKey(hive, WINDOWS_SETTINGS_KEY) as key:
                value, _typ = winreg.QueryValueEx(key, "wsnetSettings")
        except OSError as exc:
            last_error = exc
            continue
        if isinstance(value, bytes):
            value = value.decode("utf-8", "replace")
        value = str(value).lstrip("\ufeff").strip()
        if value:
            return value
    raise FileNotFoundError(
        "Windscribe settings were not found in HKCU\\" + WINDOWS_SETTINGS_KEY
    ) from last_error


def servers_from_settings(text):
    settings = json.loads(text)
    inventory = json.loads(settings["invLocations"])
    servers = []
    seen = set()
    for loc in inventory["data"]["locations"]:
        country = (loc.get("country_code") or "").strip()
        for dc in loc.get("datacenters") or []:
            if dc.get("status") != 1:
                continue
            city = (dc.get("city") or "").strip()
            nick = (dc.get("nick") or "").strip()
            if not nick or nick in seen:
                continue
            seen.add(nick)
            label = f"{city} - {nick}" if city else nick
            if country:
                label = f"{label} ({country})"
            servers.append((label, nick))
    servers.sort(key=lambda item: item[0].lower())
    return servers


def servers_from_cli_text(text):
    """Parse `Region - City - Nickname` lines. Skip JSON log lines."""
    servers = []
    seen = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("{") or line.lower().startswith("windscribe"):
            continue
        parts = [part.strip() for part in re.split(r"\s+-\s+", line) if part.strip()]
        if len(parts) < 2:
            continue
        nick = parts[-1]
        city = parts[-2]
        if not nick or nick.lower() in {"nickname", "location", "locations"}:
            continue
        if nick in seen:
            continue
        seen.add(nick)
        servers.append((f"{city} - {nick}", nick))
    servers.sort(key=lambda item: item[0].lower())
    return servers


def parse_ping_ms(stdout):
    """Average RTT from macOS or Windows ping output."""
    mac = re.search(r"min/avg/max/[a-z]+ = [\d.]+/([\d.]+)/", stdout)
    if mac:
        return round(float(mac.group(1)), 1)
    windows = re.search(
        r"(?:Average|Mittelwert|Moyenne|Media|Gemiddelde|Média)\s*=\s*([\d.]+)\s*ms",
        stdout,
        re.I,
    )
    if windows:
        return round(float(windows.group(1)), 1)
    samples = [float(n) for n in re.findall(r"(?:time|zeit|temps|tiempo|tempo)\s*=\s*([\d.]+)\s*ms", stdout, re.I)]
    samples.extend(1.0 for _ in re.findall(r"(?:time|zeit|temps)\s*<\s*1\s*ms", stdout, re.I))
    if samples:
        return round(sum(samples) / len(samples), 1)
    return None


def ping_command(target):
    if IS_WINDOWS:
        return ["ping", "-n", "3", "-w", "2000", target]
    return ["ping", "-c", "3", "-W", "2000", target]

# Supported Windscribe CLI protocols
PROTOCOLS = ["wireguard", "ikev2", "udp", "tcp", "stealth", "wstunnel"]

class WindscribeTesterApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Windscribe Server & Protocol Tester")
        self.root.geometry("950x680")
        self.root.minsize(850, 600)

        # State variables
        self.cli_path = self.detect_cli_path()
        self.is_testing = False
        self.cancel_requested = False
        self.test_results = []
        self.selected_servers = []
        self.server_targets = {}
        self.all_servers = []

        self.build_ui()
        self.reload_servers()

    def detect_cli_path(self):
        """Finds windscribe-cli on macOS or Windows."""
        which_path = shutil.which("windscribe-cli") or shutil.which("windscribe-cli.exe")
        if which_path:
            return which_path

        if IS_WINDOWS:
            program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
            program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
            candidates = [
                os.path.join(program_files, "Windscribe", "windscribe-cli.exe"),
                os.path.join(program_files_x86, "Windscribe", "windscribe-cli.exe"),
            ]
        else:
            candidates = [
                "/usr/local/bin/windscribe-cli",
                "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli",
                "/Applications/Windscribe.app/Contents/Resources/windscribe-cli",
            ]
        for path in candidates:
            if path and os.path.exists(path):
                return path
        return candidates[0]

    def build_ui(self):
        # --- Top Settings Bar ---
        settings_frame = ttk.LabelFrame(self.root, text="Configuration & Settings", padding=(10, 5))
        settings_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(settings_frame, text="CLI Path:").grid(row=0, column=0, sticky="w", padx=5, pady=2)
        self.cli_entry = ttk.Entry(settings_frame, width=45)
        self.cli_entry.insert(0, self.cli_path)
        self.cli_entry.grid(row=0, column=1, sticky="w", padx=5, pady=2)

        ttk.Label(settings_frame, text="Timeout per test (sec):").grid(row=0, column=2, sticky="e", padx=10, pady=2)
        self.timeout_var = tk.IntVar(value=15)
        self.timeout_spin = ttk.Spinbox(settings_frame, from_=5, to=60, textvariable=self.timeout_var, width=5)
        self.timeout_spin.grid(row=0, column=3, sticky="w", pady=2)

        ttk.Label(settings_frame, text="Ping Target:").grid(row=0, column=4, sticky="e", padx=10, pady=2)
        self.ping_target_var = tk.StringVar(value="1.1.1.1")
        ttk.Entry(settings_frame, textvariable=self.ping_target_var, width=12).grid(row=0, column=5, sticky="w", padx=5, pady=2)

        # --- Protocols Bar ---
        proto_frame = ttk.LabelFrame(self.root, text="Preselect Protocols to Test", padding=(10, 5))
        proto_frame.pack(fill="x", padx=10, pady=5)

        self.proto_vars = {}
        for idx, proto in enumerate(PROTOCOLS):
            var = tk.BooleanVar(value=(proto in ["wireguard", "ikev2", "udp"]))
            self.proto_vars[proto] = var
            cb = ttk.Checkbutton(proto_frame, text=proto.upper(), variable=var)
            cb.grid(row=0, column=idx, padx=15, pady=2, sticky="w")

        # --- Main Content Split (Left: Server Selection, Right: Results) ---
        paned = ttk.PanedWindow(self.root, orient=tk.HORIZONTAL)
        paned.pack(fill="both", expand=True, padx=10, pady=5)

        # Left Panel: Server Queue Management
        left_frame = ttk.LabelFrame(paned, text="Server Selection", padding=10)
        paned.add(left_frame, weight=1)

        # Available servers section
        avail_header = ttk.Frame(left_frame)
        avail_header.pack(fill="x")
        ttk.Label(avail_header, text="Available Servers:").pack(side="left")
        ttk.Button(avail_header, text="Reload Servers", command=self.reload_servers, width=14).pack(side="right")

        filter_row = ttk.Frame(left_frame)
        filter_row.pack(fill="x", pady=(4, 0))
        ttk.Label(filter_row, text="Filter:").pack(side="left", padx=(0, 6))
        self.filter_var = tk.StringVar()
        self.filter_var.trace_add("write", lambda *_: self.apply_server_filter())
        ttk.Entry(filter_row, textvariable=self.filter_var).pack(side="left", fill="x", expand=True)

        self.avail_listbox = tk.Listbox(left_frame, selectmode=tk.EXTENDED, height=8)
        self.avail_listbox.pack(fill="both", expand=True, pady=5)

        # Custom location input
        custom_frame = ttk.Frame(left_frame)
        custom_frame.pack(fill="x", pady=2)
        self.custom_loc_entry = ttk.Entry(custom_frame)
        self.custom_loc_entry.pack(side="left", fill="x", expand=True, padx=(0, 5))
        ttk.Button(custom_frame, text="Add Custom", command=self.add_custom_server).pack(side="right")

        # Transfer Buttons
        btn_transfer_frame = ttk.Frame(left_frame)
        btn_transfer_frame.pack(fill="x", pady=5)
        ttk.Button(btn_transfer_frame, text="↓ Add Selected to Test List ↓", command=self.add_to_test_list).pack(side="left", fill="x", expand=True, padx=2)
        ttk.Button(btn_transfer_frame, text="Clear List", command=self.clear_test_list).pack(side="right", padx=2)

        # Test Queue Listbox
        ttk.Label(left_frame, text="Servers to Test (Queue):").pack(anchor="w")
        self.queue_listbox = tk.Listbox(left_frame, selectmode=tk.EXTENDED, height=8)
        self.queue_listbox.pack(fill="both", expand=True, pady=5)
        ttk.Button(left_frame, text="Remove Selected from Queue", command=self.remove_from_test_list).pack(fill="x")

        # Right Panel: Live Results & Best Servers
        right_frame = ttk.LabelFrame(paned, text="Test Results (Automatically Sorted by Best Ping)", padding=10)
        paned.add(right_frame, weight=2)

        columns = ("rank", "server", "protocol", "status", "ping")
        self.tree = ttk.Treeview(right_frame, columns=columns, show="headings")
        self.tree.heading("rank", text="#")
        self.tree.heading("server", text="Server / Location")
        self.tree.heading("protocol", text="Protocol")
        self.tree.heading("status", text="Status")
        self.tree.heading("ping", text="Avg Ping (ms)")

        self.tree.column("rank", width=40, anchor="center")
        self.tree.column("server", width=180, anchor="w")
        self.tree.column("protocol", width=100, anchor="center")
        self.tree.column("status", width=110, anchor="center")
        self.tree.column("ping", width=100, anchor="center")

        self.tree.pack(fill="both", expand=True)

        # Quick connect button for the winning server
        ttk.Button(right_frame, text="Connect to Selected Result Now", command=self.connect_to_selected_result).pack(fill="x", pady=(8, 0))

        # --- Bottom Control & Status Bar ---
        bottom_frame = ttk.Frame(self.root, padding=(10, 8))
        bottom_frame.pack(fill="x")

        self.test_btn = ttk.Button(bottom_frame, text="▶ START TEST", command=self.start_testing)
        self.test_btn.pack(side="left", ipadx=15, ipady=5, padx=(0, 10))

        self.cancel_btn = ttk.Button(bottom_frame, text="⏹ CANCEL", command=self.cancel_testing, state=tk.DISABLED)
        self.cancel_btn.pack(side="left", ipadx=15, ipady=5)

        self.status_var = tk.StringVar(value="Ready. Add servers to the test queue and click START TEST.")
        ttk.Label(bottom_frame, textvariable=self.status_var).pack(side="left", padx=15)

        self.progress = ttk.Progressbar(bottom_frame, orient="horizontal", length=180, mode="determinate")
        self.progress.pack(side="right")

    # --- Server List Actions ---
    def load_datacenters(self):
        """Online datacenters from Windscribe settings, then the CLI."""
        try:
            return servers_from_settings(read_wsnet_settings()), "Windscribe settings"
        except Exception as settings_error:
            cli = self.cli_entry.get().strip()
            if not cli or not os.path.exists(cli):
                raise settings_error
            out = self.run_cmd([cli, "locations"], timeout=15)
            servers = servers_from_cli_text(out)
            if not servers:
                raise settings_error
            return servers, "Windscribe CLI"

    def reload_servers(self):
        try:
            servers, source = self.load_datacenters()
        except Exception as e:
            where = (
                "HKCU\\" + WINDOWS_SETTINGS_KEY
                if IS_WINDOWS
                else MAC_INVENTORY_PLIST
            )
            messagebox.showerror(
                "Servers",
                "Could not read Windscribe datacenters.\n"
                f"Looked in {where}.\n{e}",
            )
            return
        self.server_targets = {label: nick for label, nick in servers}
        self.all_servers = [label for label, _nick in servers]
        self.apply_server_filter()
        shown = self.avail_listbox.size()
        self.status_var.set(
            f"Loaded {len(self.all_servers)} servers from {source}. Showing {shown}. "
            "Connect uses each server nickname."
        )

    def apply_server_filter(self):
        query = self.filter_var.get().strip().lower()
        self.avail_listbox.delete(0, tk.END)
        for label in self.all_servers:
            if not query or query in label.lower():
                self.avail_listbox.insert(tk.END, label)

    def connect_name(self, label):
        return self.server_targets.get(label, label)

    def add_custom_server(self):
        val = self.custom_loc_entry.get().strip()
        if val and val not in self.queue_listbox.get(0, tk.END):
            self.queue_listbox.insert(tk.END, val)
            self.custom_loc_entry.delete(0, tk.END)

    def add_to_test_list(self):
        selected_indices = self.avail_listbox.curselection()
        current_queue = self.queue_listbox.get(0, tk.END)
        for i in selected_indices:
            loc = self.avail_listbox.get(i)
            if loc not in current_queue:
                self.queue_listbox.insert(tk.END, loc)

    def remove_from_test_list(self):
        for i in reversed(self.queue_listbox.curselection()):
            self.queue_listbox.delete(i)

    def clear_test_list(self):
        self.queue_listbox.delete(0, tk.END)

    # --- Testing Engine ---
    def start_testing(self):
        servers = list(self.queue_listbox.get(0, tk.END))
        protocols = [p for p, var in self.proto_vars.items() if var.get()]

        if not servers:
            messagebox.showwarning("No Servers", "Please add at least one server to the 'Servers to Test' queue.")
            return
        if not protocols:
            messagebox.showwarning("No Protocols", "Please check at least one protocol to test.")
            return

        cli = self.cli_entry.get().strip()
        if not os.path.exists(cli):
            messagebox.showerror("CLI Error", f"Windscribe CLI binary not found at:\n{cli}")
            return

        # Prepare UI for testing
        self.is_testing = True
        self.cancel_requested = False
        self.test_results.clear()
        for item in self.tree.get_children():
            self.tree.delete(item)

        self.test_btn.config(state=tk.DISABLED)
        self.cancel_btn.config(state=tk.NORMAL)

        total_steps = len(servers) * len(protocols)
        self.progress["maximum"] = total_steps
        self.progress["value"] = 0

        # Run tests in background thread so UI stays responsive
        threading.Thread(target=self.run_test_worker, args=(cli, servers, protocols), daemon=True).start()

    def cancel_testing(self):
        if self.is_testing:
            self.cancel_requested = True
            self.status_var.set("Cancelling test... Disconnecting and sorting current results...")
            self.cancel_btn.config(state=tk.DISABLED)

    def run_test_worker(self, cli, servers, protocols):
        timeout_sec = self.timeout_var.get()
        ping_target = self.ping_target_var.get().strip() or "1.1.1.1"
        step = 0

        for server in servers:
            if self.cancel_requested:
                break
            for proto in protocols:
                if self.cancel_requested:
                    break

                step += 1
                self.update_status(f"Testing [{step}/{int(self.progress['maximum'])}]: {server} ({proto.upper()}) - Timeout: {timeout_sec}s...")

                # 1. Disconnect cleanly before test
                self.run_cmd([cli, "disconnect"], timeout=5)

                # 2. Attempt Connection with user's timeout
                connected = self.attempt_connection(cli, self.connect_name(server), proto, timeout_sec)

                if self.cancel_requested:
                    break

                # 3. If connected, measure ping
                if connected:
                    self.update_status(f"Connected to {server} ({proto.upper()}). Measuring ping...")
                    avg_ping = self.measure_ping(ping_target, timeout=min(8, timeout_sec))
                    if avg_ping is not None:
                        self.record_result(server, proto.upper(), "SUCCESS", avg_ping)
                    else:
                        self.record_result(server, proto.upper(), "PING FAILED", None)
                else:
                    self.record_result(server, proto.upper(), "TIMEOUT / FAIL", None)

                self.root.after(0, lambda s=step: self.progress.configure(value=s))

        # Clean up VPN connection when done or cancelled
        self.run_cmd([cli, "disconnect"], timeout=5)
        self.root.after(0, self.finish_testing)

    def attempt_connection(self, cli, server, proto, timeout_sec):
        """Starts windscribe connect and polls status until Connected or timeout."""
        start_time = time.time()
        try:
            # Launch connect command (different CLI versions accept `connect "Location" protocol` or `--protocol`)
            proc = subprocess.Popen(
                [cli, "connect", server, proto],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                **subprocess_kwargs(),
            )

            while time.time() - start_time < timeout_sec:
                if self.cancel_requested:
                    proc.terminate()
                    return False

                # Check if CLI command finished and verify tunnel status
                status_out = self.run_cmd([cli, "status"], timeout=3)
                if "Connected" in status_out and "Disconnected" not in status_out:
                    return True

                time.sleep(1)

            # Timed out
            if proc.poll() is None:
                proc.terminate()
            return False
        except Exception:
            return False

    def measure_ping(self, target, timeout=6):
        """Runs the platform ping command and parses the average RTT in ms."""
        try:
            res = subprocess.run(
                ping_command(target),
                capture_output=True,
                text=True,
                timeout=timeout,
                **subprocess_kwargs(),
            )
            return parse_ping_ms(res.stdout)
        except Exception:
            return None

    def run_cmd(self, cmd_list, timeout=5):
        try:
            res = subprocess.run(
                cmd_list,
                capture_output=True,
                text=True,
                timeout=timeout,
                errors="replace",
                **subprocess_kwargs(),
            )
            return res.stdout + res.stderr
        except Exception:
            return ""

    def record_result(self, server, proto, status, ping):
        self.test_results.append({
            "server": server,
            "protocol": proto,
            "status": status,
            "ping": ping
        })
        # Re-sort live so the user always sees the best servers at the top
        self.root.after(0, self.refresh_results_table)

    def refresh_results_table(self):
        # Sort successful pings first (lowest ms to highest), then failed tests at the bottom
        sorted_results = sorted(
            self.test_results,
            key=lambda x: (x["ping"] is None, x["ping"] if x["ping"] is not None else 999999)
        )

        for item in self.tree.get_children():
            self.tree.delete(item)

        rank = 1
        for r in sorted_results:
            if r["ping"] is not None:
                ping_Display = f"{r['ping']} ms"
                rank_display = f"#{rank}"
                rank += 1
            else:
                ping_Display = "—"
                rank_display = "-"

            self.tree.insert("", tk.END, values=(
                rank_display,
                r["server"],
                r["protocol"],
                r["status"],
                ping_Display
            ))

    def finish_testing(self):
        self.is_testing = False
        self.test_btn.config(state=tk.NORMAL)
        self.cancel_btn.config(state=tk.DISABLED)
        self.refresh_results_table()

        successful = [r for r in self.test_results if r["ping"] is not None]
        if self.cancel_requested:
            self.status_var.set(f"Test cancelled. Showing {len(successful)} successful connections sorted by lowest ping.")
        else:
            self.status_var.set(f"Test complete! Found {len(successful)} working configurations sorted by lowest ping.")

    def update_status(self, msg):
        self.root.after(0, lambda: self.status_var.set(msg))

    def connect_to_selected_result(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Select a Row", "Click a server row in the results table first.")
            return
        values = self.tree.item(sel[0], "values")
        server, proto = values[1], values[2].lower()
        target = self.connect_name(server)
        cli = self.cli_entry.get().strip()

        self.status_var.set(f"Connecting to {server} via {proto.upper()}...")
        threading.Thread(
            target=lambda: subprocess.run(
                [cli, "connect", target, proto],
                **subprocess_kwargs(),
            ),
            daemon=True
        ).start()


if __name__ == "__main__":
    root = tk.Tk()
    app = WindscribeTesterApp(root)
    root.mainloop()