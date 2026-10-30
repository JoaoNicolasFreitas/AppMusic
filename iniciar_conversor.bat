@echo off
chcp 65001 > nul
title AppMusic - Conversor YouTube para MP3
cls

echo ===================================================================
echo     🎵 AppMusic - Conversor YouTube para MP3 (yt-dlp + FFmpeg)
echo ===================================================================
echo.

where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRO] Python não foi encontrado no sistema!
    echo Por favor, instale o Python em https://www.python.org/downloads/
    echo e marque a opção "Add Python to PATH".
    pause
    exit /b 1
)

echo [*] Verificando dependências do conversor...
python -m pip install yt-dlp imageio-ffmpeg mutagen --quiet --disable-pip-version-check

echo [*] Iniciando o conversor com interface gráfica...
start "" python "%~dp0python_converter\converter_gui.py"

echo [OK] O conversor foi aberto com sucesso!
exit /b 0
