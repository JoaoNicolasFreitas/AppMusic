"""
Servidor REST API local para converter e baixar músicas para o AppMusic (Flutter).
Permite que o aplicativo no celular conecte diretamente e baixe em MP3/M4A/MP4 via yt-dlp + FFmpeg.
"""

import http.server
import json
import os
import re
import socket
import socketserver
import sys
import tempfile
import threading
import urllib.parse
from typing import Optional

from converter import (
    download_audio_to_m4a,
    download_audio_to_mp3,
    download_video_to_mp4,
    extract_info,
    get_default_download_dir,
)

PORT = 5000


def get_local_ip() -> str:
    """Detecta o IP da máquina na rede local Wi-Fi / Ethernet."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class ConverterAPIHandler(http.server.BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Range")

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if parsed.path in ("/", "/health", "/api/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._send_cors_headers()
            self.end_headers()
            data = {
                "status": "ok",
                "service": "AppMusic Python Converter API",
                "version": "1.1.0",
                "ip": get_local_ip(),
                "port": PORT,
            }
            self.wfile.write(json.dumps(data, indent=2).encode("utf-8"))
            return

        # 1. Obter metadados do vídeo
        if parsed.path == "/api/info":
            url = params.get("url", [None])[0]
            if not url:
                self._send_error(400, "Parâmetro 'url' obrigatório.")
                return
            try:
                info = extract_info(url)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps(info, ensure_ascii=False).encode("utf-8"))
            except Exception as e:
                self._send_error(500, f"Erro ao consultar vídeo: {e}")
            return

        # 2. Download direto com stream para o celular / navegador
        if parsed.path == "/api/download":
            url = params.get("url", [None])[0]
            fmt = params.get("format", ["mp3"])[0].lower()
            quality = params.get("quality", ["128"])[0]

            if not url:
                self._send_error(400, "Parâmetro 'url' obrigatório.")
                return

            temp_dir = tempfile.mkdtemp(prefix="appmusic_conv_")
            try:
                print(f"[API] 📥 Início de download: formato={fmt}, qualidade={quality}, URL={url}")
                if fmt == "mp4":
                    filepath = download_video_to_mp4(url, output_dir=temp_dir)
                    content_type = "video/mp4"
                    target_ext = ".mp4"
                elif fmt in ("m4a", "aac"):
                    filepath = download_audio_to_m4a(url, output_dir=temp_dir)
                    content_type = "audio/mp4"
                    target_ext = ".m4a"
                else:
                    filepath = download_audio_to_mp3(url, output_dir=temp_dir, quality=quality)
                    content_type = "audio/mpeg"
                    target_ext = ".mp3"

                if not os.path.isfile(filepath):
                    # Procura pelo arquivo correto na pasta temporária
                    candidates = [
                        os.path.join(temp_dir, f)
                        for f in os.listdir(temp_dir)
                        if f.lower().endswith(target_ext)
                    ]
                    if candidates:
                        candidates.sort(key=lambda p: os.path.getsize(p), reverse=True)
                        filepath = candidates[0]
                    else:
                        files = [os.path.join(temp_dir, f) for f in os.listdir(temp_dir)]
                        if files:
                            filepath = files[0]
                        else:
                            raise FileNotFoundError(f"Nenhum arquivo {target_ext} gerado no processo.")

                file_size = os.path.getsize(filepath)
                filename = os.path.basename(filepath)

                # Tratamento crucial de cabeçalhos HTTP:
                # O atributo filename="..." requer ASCII puro para não falhar na codificação latin-1 do http.server.
                # O nome completo em UTF-8 (acentos, emojis, aspas) é preservado no filename*=UTF-8''...
                ascii_filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
                safe_utf8_filename = urllib.parse.quote(filename)

                print(f"[API] 📤 Enviando '{filename}' ({file_size} bytes, {content_type})...")
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(file_size))
                self.send_header(
                    "Content-Disposition",
                    f'attachment; filename="{ascii_filename}"; filename*=UTF-8\'\'{safe_utf8_filename}',
                )
                self._send_cors_headers()
                self.end_headers()

                with open(filepath, "rb") as f:
                    while chunk := f.read(65536):
                        self.wfile.write(chunk)
                print(f"[API] ✅ Envio de '{filename}' finalizado com 100% de sucesso!")
            except Exception as e:
                print(f"[API] ❌ Erro durante download/conversão: {e}")
                try:
                    self._send_error(500, f"Erro na conversão: {e}")
                except Exception:
                    pass
            finally:
                try:
                    import shutil
                    shutil.rmtree(temp_dir, ignore_errors=True)
                except Exception:
                    pass
            return

        self._send_error(404, "Endpoint não encontrado.")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/convert":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            try:
                data = json.loads(body)
                urls = data.get("urls", [])
                if isinstance(urls, str):
                    urls = [urls]
                fmt = data.get("format", "mp3")
                quality = data.get("quality", "320")
                dest = data.get("output_dir") or str(get_default_download_dir())

                results = []
                for u in urls:
                    try:
                        if fmt == "mp4":
                            f = download_video_to_mp4(u, output_dir=dest)
                        elif fmt in ("m4a", "aac"):
                            f = download_audio_to_m4a(u, output_dir=dest)
                        else:
                            f = download_audio_to_mp3(u, output_dir=dest, quality=quality)
                        results.append({"url": u, "status": "success", "file": os.path.basename(f)})
                    except Exception as err:
                        results.append({"url": u, "status": "error", "message": str(err)})

                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"results": results}, ensure_ascii=False).encode("utf-8"))
            except Exception as e:
                self._send_error(400, f"JSON inválido: {e}")
            return

        self._send_error(404, "Endpoint não encontrado.")

    def _send_error(self, code: int, message: str):
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._send_cors_headers()
            self.end_headers()
            err_data = {"error": message, "code": code}
            self.wfile.write(json.dumps(err_data, ensure_ascii=False).encode("utf-8"))
        except Exception:
            pass

    def log_message(self, format, *args):
        # Log simplificado com IP do cliente
        sys.stdout.write(f"[API {self.address_string()}] {format % args}\n")
        sys.stdout.flush()


def run_server(port: int = PORT):
    server = ThreadedHTTPServer(("0.0.0.0", port), ConverterAPIHandler)
    local_ip = get_local_ip()
    print("=" * 65)
    print(f"🎵 AppMusic Converter API Server Rodando na Porta {port}")
    print(f"👉 Local:   http://127.0.0.1:{port}")
    print(f"👉 Celular: http://{local_ip}:{port}")
    print("=" * 65)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServidor encerrado pelo usuário.")
    finally:
        server.server_close()


if __name__ == "__main__":
    run_server()
