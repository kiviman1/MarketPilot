"""Manual Windows companion. Only the worker reads HTTP or writes ExternalData.lua."""
from pathlib import Path
import os
import queue
import threading
import tkinter as tk
from tkinter import filedialog, ttk
import webbrowser

try:
    from .engine import Client, SyncError, load_catalog, validate_destination, write_payload
except ImportError:  # Double-click / direct pythonw launch.
    from engine import Client, SyncError, load_catalog, validate_destination, write_payload

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TARGET = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
    "World of Warcraft/_classic_beta_/Interface/AddOns/MarketPilotDev"
)


class Jobs:
    """One user-requested desktop operation at a time; no scheduled downloads."""
    def __init__(self):
        self.busy = False
        self.events = queue.Queue()

    def start(self, action):
        if self.busy:
            return False
        self.busy = True

        def worker():
            try:
                self.events.put(("success", action()))
            except Exception as error:
                self.events.put(("error", str(error)))
            finally:
                self.events.put(("finished", None))
        self.worker = threading.Thread(target=worker, name="MarketPilotSync", daemon=True)
        self.worker.start()
        return True

    def progress(self, done, total, message):
        self.events.put(("progress", (done, total, message)))

    def drain(self):
        events = []
        while True:
            try:
                event = self.events.get_nowait()
            except queue.Empty:
                return events
            if event[0] == "finished":
                self.busy = False
            events.append(event)


class App:
    def __init__(self, root, client=None):
        self.root, self.client, self.jobs = root, client or Client(), Jobs()
        self.markets, self.market_labels = [], []
        self.operation = None
        self.item_ids = []
        self.target = tk.StringVar(value=str(DEFAULT_TARGET))
        self.selection = tk.StringVar()
        self.status = tk.StringVar(value="Pazar listesi yükleniyor…")
        self.message = tk.StringVar(value="Bir pazar seç. Güncelleme yalnız düğmeye bastığında çalışır.")
        self.root.title("MarketPilot Sync")
        logo = ROOT / "assets/MarketPilot-CurseForge.png"
        if logo.is_file():
            self.logo = tk.PhotoImage(file=str(logo)).subsample(4)
            self.root.iconphoto(True, self.logo)
        self.root.geometry("840x600")
        self.root.minsize(780, 580)
        self.root.configure(bg="#0c1118")
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        style = ttk.Style(root)
        style.theme_use("clam")
        style.configure("TFrame", background="#0c1118")
        style.configure("TLabel", background="#0c1118", foreground="#dbe4ef", font=("Segoe UI", 10))
        style.configure("Title.TLabel", font=("Segoe UI", 21, "bold"), foreground="#ffcb4a")
        style.configure("Muted.TLabel", foreground="#9aaec7")
        style.configure("TButton", font=("Segoe UI", 10), padding=(12, 8), background="#27344b", foreground="#ecf1f7")
        style.map("TButton", foreground=[("disabled", "#8190a3")])
        style.configure("TEntry", fieldbackground="#18202e", foreground="#ecf1f7", padding=6)
        style.configure("TCombobox", fieldbackground="#18202e", foreground="#ecf1f7", padding=6)
        style.map("TCombobox", fieldbackground=[("readonly", "#18202e")], foreground=[("readonly", "#ecf1f7")])
        style.configure("Horizontal.TProgressbar", background="#ffcb4a", troughcolor="#18202e")
        content = ttk.Frame(root, padding=24)
        content.pack(fill="both", expand=True)
        content.columnconfigure(0, weight=1)
        ttk.Label(content, text="MarketPilot Sync", style="Title.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(content, text="Gathering materyalleri · Fiyat ve geçmiş · Manuel güncelleme",
                  style="Muted.TLabel").grid(row=1, column=0, sticky="w", pady=(6, 22))
        ttk.Label(content, text="AHledger pazarı").grid(row=2, column=0, sticky="w")
        market_row = ttk.Frame(content)
        market_row.grid(row=3, column=0, sticky="ew", pady=(6, 16))
        market_row.columnconfigure(0, weight=1)
        self.market_box = ttk.Combobox(market_row, textvariable=self.selection, state="readonly")
        self.market_box.grid(row=0, column=0, sticky="ew")
        self.market_box.bind("<<ComboboxSelected>>", lambda _: self.controls())
        self.reload_button = ttk.Button(market_row, text="Listeyi yenile", command=self.load_markets)
        self.reload_button.grid(row=0, column=1, padx=(10, 0))
        ttk.Label(content, text="Addon klasörü (MarketPilot Dev)").grid(row=4, column=0, sticky="w")
        target_row = ttk.Frame(content)
        target_row.grid(row=5, column=0, sticky="ew", pady=(6, 16))
        target_row.columnconfigure(0, weight=1)
        self.target_entry = ttk.Entry(target_row, textvariable=self.target)
        self.target_entry.grid(row=0, column=0, sticky="ew")
        self.browse_button = ttk.Button(target_row, text="Klasör seç", command=self.browse)
        self.browse_button.grid(row=0, column=1, padx=(10, 0))
        self.update_button = ttk.Button(content, text="Şimdi güncelle", command=self.update)
        self.update_button.grid(row=6, column=0, sticky="w", pady=(2, 12))
        self.progress_bar = ttk.Progressbar(content, mode="determinate", maximum=1)
        self.progress_bar.grid(row=7, column=0, sticky="ew", pady=(0, 12))
        ttk.Label(content, textvariable=self.status).grid(row=8, column=0, sticky="w")
        ttk.Label(content, textvariable=self.message, wraplength=740, style="Muted.TLabel").grid(
            row=9, column=0, sticky="nw", pady=(8, 16))
        content.rowconfigure(9, weight=1)
        ttk.Label(content, text="Güncellemeden sonra oyunda /reload → /mpdev external\n"
                  "Yerel tarama geçmişi ayrı kalır. Pazar eşleşmesi otomatik varsayılmaz.",
                  style="Muted.TLabel").grid(row=10, column=0, sticky="w", pady=(0, 10))
        link = ttk.Label(content, text="Kaynak: AHledger · https://ahledger.com", foreground="#77b4ff", cursor="hand2")
        link.grid(row=11, column=0, sticky="w")
        link.bind("<Button-1>", lambda _: webbrowser.open("https://ahledger.com"))
        self.root.after(100, self.receive)
        self.load_markets()

    def controls(self):
        state = "disabled" if self.jobs.busy else "normal"
        for button in (self.reload_button, self.browse_button):
            button.configure(state=state)
        self.target_entry.configure(state=state)
        self.market_box.configure(state="disabled" if self.jobs.busy else "readonly")
        selected = self.selection.get() in self.market_labels
        self.update_button.configure(state="normal" if selected and not self.jobs.busy else "disabled")

    def browse(self):
        selected = filedialog.askdirectory(parent=self.root, title="MarketPilotDev addon klasörünü seç",
                                           initialdir=str(DEFAULT_TARGET.parent), mustexist=True)
        if selected:
            self.target.set(selected)

    def load_markets(self):
        if self.jobs.busy:
            return
        self.operation = "markets"
        self.status.set("Pazar listesi yükleniyor…")
        self.jobs.start(self.client.markets)
        self.controls()

    def update(self):
        if self.jobs.busy or self.selection.get() not in self.market_labels:
            return
        market = dict(self.markets[self.market_labels.index(self.selection.get())])
        try:
            destination = validate_destination(Path(self.target.get()))
            # Use the selected installed catalogue, so an older compatible
            # install never receives IDs its Lua consumer would reject.
            self.item_ids = load_catalog(destination / "Items.lua")
        except (SyncError, OSError, ValueError) as error:
            self.status.set("Güncelleme başlamadı")
            self.message.set(str(error))
            return
        self.operation = "update"
        self.status.set("Veri indiriliyor…")
        self.message.set("Tüm yanıtlar doğrulandıktan sonra veri dosyası değiştirilecek.")
        self.progress_bar.configure(value=0, maximum=len(self.item_ids) * 2)

        def action():
            payload = self.client.update(market, self.item_ids, self.jobs.progress)
            path = write_payload(destination, payload)
            priced = sum(1 for item in payload["items"].values() if item.get("latest", {}).get("median") is not None)
            return path, priced, len(self.item_ids), market["label"]
        self.jobs.start(action)
        self.controls()

    def receive(self):
        for kind, value in self.jobs.drain():
            if kind == "progress":
                done, total, message = value
                self.progress_bar.configure(value=done, maximum=total)
                self.status.set(f"İndiriliyor: {done}/{total}")
                self.message.set(message)
            elif kind == "error":
                self.status.set("Güncelleme başarısız" if self.operation == "update" else "Pazar listesi alınamadı")
                self.message.set(f"{value}\nSon başarılı veri dosyası korundu. Daha sonra yeniden deneyebilirsin.")
            elif kind == "success" and self.operation == "markets":
                previous = self.selection.get()
                self.markets = value
                self.market_labels = [f'{m["label"]} · {m["region"].upper()} · {m["id"]}' for m in value]
                self.market_box.configure(values=self.market_labels)
                self.selection.set(previous if previous in self.market_labels else "")
                self.status.set("Pazar listesi hazır")
                self.message.set("Karakterinin oynadığı pazarı seç. Liste sunucudan alınır; yerel realm ile otomatik eşleştirilmez.")
            elif kind == "success":
                path, priced, count, label = value
                self.status.set(f"Güncellendi · {label} · {priced}/{count} materyalde fiyat var")
                self.message.set(f"{path}\nOyunda /reload yapıp AHledger sekmesini aç. Fiyatı olmayan materyaller boş kalır.")
            elif kind == "finished":
                self.controls()
        self.root.after(100, self.receive)

    def close(self):
        if self.jobs.busy:
            self.message.set("Güncelleme bitince pencereyi kapatabilirsin.")
            return
        self.root.destroy()


def main():
    root = tk.Tk()
    try:
        App(root)
    except Exception as error:
        from tkinter import messagebox
        messagebox.showerror("MarketPilot Sync", f"Uygulama açılamadı:\n{error}", parent=root)
        root.destroy()
        return
    root.mainloop()


if __name__ == "__main__":
    main()
