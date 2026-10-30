"""
Aplicativo Desktop Conversor de YouTube para MP3 / M4A / MP4.
Inspirado no projeto DorianNaaji/Youtube-To-MP3-Converter.
Interface gráfica moderna em Tkinter, com suporte a múltiplos links e servidor API para celular.
"""

import os
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from converter import (
    download_audio_to_m4a,
    download_audio_to_mp3,
    download_video_to_mp4,
    extract_info,
    get_default_download_dir,
)
from converter_server import ConverterAPIHandler, PORT, ThreadedHTTPServer, get_local_ip


class YoutubeToMp3App:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("AppMusic - YouTube to MP3 Converter (yt-dlp + FFmpeg)")
        self.root.geometry("780x680")
        self.root.minsize(700, 580)
        self.root.configure(bg="#121218")

        self.download_dir = str(get_default_download_dir())
        self.is_converting = False
        self.api_server = None
        self.api_thread = None

        self._apply_styles()
        self._build_ui()

    def _apply_styles(self):
        style = ttk.Style()
        style.theme_use("clam")

        style.configure(".", background="#121218", foreground="#FFFFFF")
        style.configure("TLabel", background="#121218", foreground="#E0E0E0", font=("Segoe UI", 10))
        style.configure("Header.TLabel", background="#121218", foreground="#BB86FC", font=("Segoe UI", 16, "bold"))
        style.configure("Sub.TLabel", background="#121218", foreground="#A0A0B0", font=("Segoe UI", 9))

        style.configure("TButton", font=("Segoe UI", 10, "bold"), padding=6, background="#2A2A38", foreground="#FFFFFF")
        style.map("TButton", background=[("active", "#7C4DFF"), ("pressed", "#651FFF")])

        style.configure("Primary.TButton", font=("Segoe UI", 11, "bold"), padding=8, background="#7C4DFF", foreground="#FFFFFF")
        style.map("Primary.TButton", background=[("active", "#9E75FF"), ("pressed", "#651FFF")])

        style.configure("Success.TButton", font=("Segoe UI", 10, "bold"), padding=6, background="#00C853", foreground="#FFFFFF")
        style.map("Success.TButton", background=[("active", "#69F0AE"), ("pressed", "#00B248")])

        style.configure("TProgressbar", thickness=14, troughcolor="#1E1E2A", background="#7C4DFF")

    def _build_ui(self):
        # 1. Cabeçalho
        header_frame = tk.Frame(self.root, bg="#121218")
        header_frame.pack(fill=tk.X, padx=20, pady=(15, 5))

        lbl_title = ttk.Label(header_frame, text="🎵 AppMusic - Conversor YouTube para MP3 / M4A / MP4", style="Header.TLabel")
        lbl_title.pack(anchor="w")

        lbl_desc = ttk.Label(
            header_frame,
            text="Baixe e converta links do YouTube para MP3 de alta fidelidade sem nenhum erro 403 (yt-dlp + FFmpeg).",
            style="Sub.TLabel",
        )
        lbl_desc.pack(anchor="w", pady=(2, 0))

        # 2. Área de Texto para Links
        box_frame = tk.Frame(self.root, bg="#181822", bd=1, relief=tk.SOLID)
        box_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)

        lbl_links = tk.Label(
            box_frame,
            text="Links do YouTube (um por linha):",
            bg="#181822",
            fg="#BB86FC",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        )
        lbl_links.pack(fill=tk.X, padx=12, pady=(10, 4))

        self.txt_links = tk.Text(
            box_frame,
            height=6,
            bg="#101016",
            fg="#FFFFFF",
            insertbackground="#BB86FC",
            font=("Consolas", 10),
            bd=0,
            padx=10,
            pady=8,
            relief=tk.FLAT,
        )
        self.txt_links.pack(fill=tk.BOTH, expand=True, padx=12, pady=(0, 10))

        # 3. Configurações de Formato e Pasta
        cfg_frame = tk.Frame(self.root, bg="#121218")
        cfg_frame.pack(fill=tk.X, padx=20, pady=4)

        tk.Label(cfg_frame, text="Qualidade / Formato:", bg="#121218", fg="#E0E0E0", font=("Segoe UI", 9, "bold")).grid(
            row=0, column=0, sticky="w", padx=(0, 10)
        )
        self.var_format = tk.StringVar(value="MP3 - 128 kbps (Otimizado · Leve ~3 MB · Recomendado)")
        formats = [
            "MP3 - 128 kbps (Otimizado · Leve ~3 MB · Recomendado)",
            "M4A - Áudio AAC (Nativo do YouTube · ~3 MB · Rápido)",
            "MP3 - 192 kbps (Alta Qualidade · ~5 MB)",
            "MP3 - 320 kbps (Máxima Fidelidade · ~9 MB)",
            "MP4 - Vídeo 720p HD (Otimizado · Com Capa)",
        ]
        self.cmb_format = ttk.Combobox(cfg_frame, textvariable=self.var_format, values=formats, state="readonly", width=38)
        self.cmb_format.grid(row=0, column=1, sticky="w", pady=4)

        # Pasta de Saída
        tk.Label(cfg_frame, text="Pasta de Saída:", bg="#121218", fg="#E0E0E0", font=("Segoe UI", 9, "bold")).grid(
            row=1, column=0, sticky="w", padx=(0, 10), pady=4
        )
        self.lbl_dir = tk.Label(
            cfg_frame,
            text=self.download_dir,
            bg="#181822",
            fg="#A0A0B0",
            font=("Segoe UI", 8),
            anchor="w",
            padx=6,
            pady=4,
            relief=tk.SUNKEN,
            bd=1,
        )
        self.lbl_dir.grid(row=1, column=1, sticky="ew", pady=4)

        btn_browse = ttk.Button(cfg_frame, text="Alterar Pasta", command=self._choose_dir)
        btn_browse.grid(row=1, column=2, padx=(8, 0))

        btn_open_folder = ttk.Button(cfg_frame, text="Abrir Pasta", command=self._open_dir)
        btn_open_folder.grid(row=1, column=3, padx=(6, 0))

        # 4. Barra de Ações Principais
        actions_frame = tk.Frame(self.root, bg="#121218")
        actions_frame.pack(fill=tk.X, padx=20, pady=10)

        self.btn_check = ttk.Button(actions_frame, text="🔍 Verificar Links", command=self._check_links)
        self.btn_check.pack(side=tk.LEFT, padx=(0, 8))

        self.btn_convert = ttk.Button(actions_frame, text="⚡ Converter para MP3", style="Primary.TButton", command=self._start_convert)
        self.btn_convert.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)

        self.btn_server = ttk.Button(
            actions_frame,
            text="🌐 Iniciar Servidor Celular",
            style="Success.TButton",
            command=self._toggle_server,
        )
        self.btn_server.pack(side=tk.RIGHT, padx=(8, 0))

        # 5. Progresso e Log
        self.progress = ttk.Progressbar(self.root, mode="indeterminate")
        self.progress.pack(fill=tk.X, padx=20, pady=(0, 6))

        log_frame = tk.Frame(self.root, bg="#181822", bd=1, relief=tk.SOLID)
        log_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=(0, 15))

        self.txt_log = tk.Text(
            log_frame,
            height=6,
            bg="#0E0E14",
            fg="#80FF80",
            font=("Consolas", 9),
            bd=0,
            padx=8,
            pady=6,
            state=tk.DISABLED,
        )
        self.txt_log.pack(fill=tk.BOTH, expand=True)

        self._log("Conversor iniciado e pronto. Cole seus links do YouTube acima e clique em 'Converter para MP3'.")

    def _log(self, text: str):
        self.txt_log.configure(state=tk.NORMAL)
        self.txt_log.insert(tk.END, text + "\n")
        self.txt_log.see(tk.END)
        self.txt_log.configure(state=tk.DISABLED)

    def _choose_dir(self):
        selected = filedialog.askdirectory(initialdir=self.download_dir)
        if selected:
            self.download_dir = selected
            self.lbl_dir.config(text=self.download_dir)

    def _open_dir(self):
        path = self.download_dir
        if os.path.exists(path):
            os.startfile(path)
        else:
            os.makedirs(path, exist_ok=True)
            os.startfile(path)

    def _check_links(self):
        urls = [line.strip() for line in self.txt_links.get("1.0", tk.END).splitlines() if line.strip()]
        if not urls:
            messagebox.showwarning("Aviso", "Cole pelo menos um link do YouTube no campo de texto.")
            return

        def _worker():
            self._log(f"--- Verificando {len(urls)} link(s) ---")
            for u in urls:
                try:
                    info = extract_info(u)
                    self._log(f"✔ [{info['title']}] - {info['uploader']}")
                except Exception as e:
                    self._log(f"✖ Falha em {u}: {e}")
            self._log("--- Fim da verificação ---")

        threading.Thread(target=_worker, daemon=True).start()

    def _start_convert(self):
        if self.is_converting:
            return

        urls = [line.strip() for line in self.txt_links.get("1.0", tk.END).splitlines() if line.strip()]
        if not urls:
            messagebox.showwarning("Aviso", "Cole pelo menos um link do YouTube no campo de texto.")
            return

        fmt_choice = self.var_format.get()
        is_mp4 = "MP4" in fmt_choice
        is_m4a = "M4A" in fmt_choice
        quality = "128"
        if "320" in fmt_choice:
            quality = "320"
        elif "192" in fmt_choice:
            quality = "192"

        self.is_converting = True
        self.btn_convert.configure(state=tk.DISABLED)
        self.progress.start(10)

        def _worker():
            total = len(urls)
            self._log(f"🚀 Iniciando conversão de {total} item(ns)...")
            success_count = 0

            for i, u in enumerate(urls, 1):
                self._log(f"\n[{i}/{total}] Processando: {u}")
                try:
                    if is_mp4:
                        res = download_video_to_mp4(u, output_dir=self.download_dir)
                    elif is_m4a:
                        res = download_audio_to_m4a(u, output_dir=self.download_dir)
                    else:
                        res = download_audio_to_mp3(u, output_dir=self.download_dir, quality=quality)
                    self._log(f"✅ Concluído com sucesso: {os.path.basename(res)}")
                    success_count += 1
                except Exception as err:
                    self._log(f"❌ Erro ao converter {u}: {err}")

            self.root.after(0, self._finish_convert, success_count, total)

        threading.Thread(target=_worker, daemon=True).start()

    def _finish_convert(self, success: int, total: int):
        self.is_converting = False
        self.btn_convert.configure(state=tk.NORMAL)
        self.progress.stop()
        self._log(f"\n🎉 Processamento finalizado! {success} de {total} arquivos convertidos.")
        if messagebox.askyesno("Sucesso", f"{success} arquivo(s) convertidos com sucesso!\nDeseja abrir a pasta agora?"):
            self._open_dir()

    def _toggle_server(self):
        if self.api_server is None:
            try:
                local_ip = get_local_ip()
                self.api_server = ThreadedHTTPServer(("0.0.0.0", PORT), ConverterAPIHandler)
                self.api_thread = threading.Thread(target=self.api_server.serve_forever, daemon=True)
                self.api_thread.start()
                self.btn_server.configure(text="🛑 Parar Servidor", style="TButton")
                self._log(f"\n🌐 Servidor API ativo na porta {PORT}!")
                self._log(f"👉 Endereço para conectar o AppMusic no celular: http://{local_ip}:{PORT}")
                messagebox.showinfo(
                    "Servidor Ativo",
                    f"Servidor para o celular iniciado com sucesso!\n\n"
                    f"No AppMusic (no celular conectado no mesmo Wi-Fi), o app pode conectar em:\n"
                    f"http://{local_ip}:{PORT}",
                )
            except Exception as e:
                messagebox.showerror("Erro no Servidor", f"Não foi possível iniciar o servidor: {e}")
        else:
            try:
                self.api_server.shutdown()
                self.api_server.server_close()
                self.api_server = None
                self.btn_server.configure(text="🌐 Iniciar Servidor Celular", style="Success.TButton")
                self._log("\n🛑 Servidor API encerrado.")
            except Exception as e:
                self._log(f"Erro ao encerrar servidor: {e}")


def main():
    root = tk.Tk()
    app = YoutubeToMp3App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
