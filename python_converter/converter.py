"""
Módulo principal do Conversor de YouTube para MP3 / M4A / MP4.
Baseado no padrão yt-dlp + FFmpeg + Mutagen (inspirado em DorianNaaji/Youtube-To-MP3-Converter).
Com embutimento automático de capa (Thumbnail Artwork) e otimização de tamanho de arquivo.
"""

import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any, Callable, Dict, Optional

import imageio_ffmpeg
import yt_dlp

# Garante que o executável ffmpeg.exe existe na pasta de binários e está no PATH do sistema
def _setup_ffmpeg() -> str:
    ffmpeg_src = imageio_ffmpeg.get_ffmpeg_exe()
    ffmpeg_dir = os.path.dirname(ffmpeg_src)
    ffmpeg_exe = os.path.join(ffmpeg_dir, 'ffmpeg.exe')
    if not os.path.exists(ffmpeg_exe):
        try:
            shutil.copyfile(ffmpeg_src, ffmpeg_exe)
        except Exception:
            pass
    if ffmpeg_dir not in os.environ.get('PATH', ''):
        os.environ['PATH'] = ffmpeg_dir + os.pathsep + os.environ.get('PATH', '')
    return ffmpeg_dir

FFMPEG_DIR = _setup_ffmpeg()


def get_default_download_dir() -> Path:
    """Retorna o diretório padrão Desktop/ConvertedMp3"""
    desktop = Path.home() / 'Desktop'
    if not desktop.exists():
        onedrive_desktop = Path.home() / 'OneDrive' / 'Desktop'
        if onedrive_desktop.exists():
            desktop = onedrive_desktop
    target = desktop / 'ConvertedMp3'
    target.mkdir(parents=True, exist_ok=True)
    return target


def extract_info(url: str) -> Dict[str, Any]:
    """Obtém os metadados do vídeo sem realizar o download."""
    ydl_opts = {
        'quiet': True,
        'skip_download': True,
        'ffmpeg_location': FFMPEG_DIR,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url.strip(), download=False)
        return {
            'id': info.get('id'),
            'title': info.get('title', 'Música'),
            'uploader': info.get('uploader') or info.get('channel') or info.get('artist', 'Artista desconhecido'),
            'duration': info.get('duration'),
            'thumbnail': info.get('thumbnail'),
            'formats_count': len(info.get('formats', [])),
        }


def download_audio_to_mp3(
    url: str,
    output_dir: Optional[str] = None,
    quality: str = '128',
    progress_callback: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> str:
    """
    Baixa o melhor fluxo de áudio do YouTube e converte para MP3 puro com FFmpeg.
    Embutimento automático da capa oficial do YouTube nos metadados ID3v2 (APIC frame).
    Otimizado para arquivo leve (~3 MB em 128 kbps).
    """
    dest_dir = Path(output_dir) if output_dir else get_default_download_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    out_template = str(dest_dir / '%(title)s.%(ext)s')

    hooks = []
    if progress_callback:
        hooks.append(progress_callback)

    ydl_opts = {
        'format': 'bestaudio[ext=m4a]/bestaudio/bestvideo+bestaudio/best',
        'ffmpeg_location': FFMPEG_DIR,
        'outtmpl': out_template,
        'writethumbnail': True,
        'progress_hooks': hooks,
        'postprocessors': [
            {
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': str(quality),
            },
            {
                'key': 'FFmpegThumbnailsConvertor',
                'format': 'jpg',
            },
            {
                'key': 'EmbedThumbnail',
                'already_have_thumbnail': False,
            },
            {
                'key': 'FFmpegMetadata',
                'add_metadata': True,
            },
        ],
        'postprocessor_args': {
            'FFmpegExtractAudio': ['-threads', '0'],
        },
        'quiet': False,
        'no_warnings': True,
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url.strip(), download=True)
        if info:
            prepared = ydl.prepare_filename(info)
            expected = os.path.splitext(prepared)[0] + '.mp3'
            if os.path.isfile(expected):
                return expected

    # Busca segura por qualquer .mp3 criado na pasta
    mp3_files = list(dest_dir.glob("*.mp3"))
    if mp3_files:
        mp3_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return str(mp3_files[0])

    return str(dest_dir)


def download_audio_to_m4a(
    url: str,
    output_dir: Optional[str] = None,
    progress_callback: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> str:
    """
    Baixa o áudio no formato nativo M4A / AAC do YouTube com capa embutida.
    Ultrarrápido, sem re-encodificação desnecessária e extremamente leve (~3 MB).
    """
    dest_dir = Path(output_dir) if output_dir else get_default_download_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    out_template = str(dest_dir / '%(title)s.%(ext)s')

    hooks = []
    if progress_callback:
        hooks.append(progress_callback)

    ydl_opts = {
        'format': 'bestaudio[ext=m4a]/bestaudio/best',
        'ffmpeg_location': FFMPEG_DIR,
        'outtmpl': out_template,
        'writethumbnail': True,
        'progress_hooks': hooks,
        'postprocessors': [
            {
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'm4a',
            },
            {
                'key': 'FFmpegThumbnailsConvertor',
                'format': 'jpg',
            },
            {
                'key': 'EmbedThumbnail',
                'already_have_thumbnail': False,
            },
            {
                'key': 'FFmpegMetadata',
                'add_metadata': True,
            },
        ],
        'quiet': False,
        'no_warnings': True,
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url.strip(), download=True)
        if info:
            prepared = ydl.prepare_filename(info)
            expected = os.path.splitext(prepared)[0] + '.m4a'
            if os.path.isfile(expected):
                return expected

    m4a_files = list(dest_dir.glob("*.m4a"))
    if m4a_files:
        m4a_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return str(m4a_files[0])

    return str(dest_dir)


def download_video_to_mp4(
    url: str,
    output_dir: Optional[str] = None,
    progress_callback: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> str:
    """
    Baixa o vídeo no formato MP4 limitado a 720p HD com capa embutida.
    Evita arquivos gigantes de 200MB+ (fica em torno de 15MB a 25MB).
    """
    dest_dir = Path(output_dir) if output_dir else get_default_download_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    out_template = str(dest_dir / '%(title)s.%(ext)s')

    hooks = []
    if progress_callback:
        hooks.append(progress_callback)

    ydl_opts = {
        # Limita a 720p para manter arquivo leve e rápido
        'format': 'bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]/best',
        'ffmpeg_location': FFMPEG_DIR,
        'outtmpl': out_template,
        'writethumbnail': True,
        'progress_hooks': hooks,
        'merge_output_format': 'mp4',
        'postprocessors': [
            {
                'key': 'FFmpegThumbnailsConvertor',
                'format': 'jpg',
            },
            {
                'key': 'EmbedThumbnail',
                'already_have_thumbnail': False,
            },
            {
                'key': 'FFmpegMetadata',
                'add_metadata': True,
            },
        ],
        'quiet': False,
        'no_warnings': True,
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url.strip(), download=True)
        if info:
            prepared = ydl.prepare_filename(info)
            expected = os.path.splitext(prepared)[0] + '.mp4'
            if os.path.isfile(expected):
                return expected

    mp4_files = list(dest_dir.glob("*.mp4"))
    if mp4_files:
        mp4_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return str(mp4_files[0])

    return str(dest_dir)
