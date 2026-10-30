# 🎵 AppMusic · Player de Música & Downloader (v0.2)

Um aplicativo moderno e fluido de reprodução de música offline para Android, desenvolvido em **Flutter** com integração nativa em **Kotlin**, suporte a reprodução em segundo plano via `audio_service`, gerenciador de playlists e favoritos, além de um sistema avançado de downloads de áudio/vídeo imune ao Erro 403.

---

## ✨ Principais Funcionalidades

### 🎧 Player Offline & Biblioteca
- **Varredura Nativa do MediaStore:** Detecção automática de todas as músicas armazenadas no dispositivo.
- **Reprodução em Segundo Plano:** Controles na barra de notificações e tela de bloqueio com suporte total a `audio_session` e `just_audio`.
- **Fila Dinâmica & Playlists:** Criação, edição, exclusão e reordenação de playlists e favoritos persistidos localmente via `sqflite`.
- **Capas dos Álbuns e Vídeos:** Cache inteligente e extração direta de metadados ID3/MP4 e miniaturas salvas do YouTube.

### ⚡ Sistema de Download Anti-Bloqueio (Zero Erro 403)
- **Fluxo Progressivo Imune ao Erro 403:** Utiliza streams progressivos estáveis (`manifest.muxed` / itag 18) que o YouTube nunca bloqueia.
- **Demuxing Nativo sem Perda (`MediaExtractor` + `MediaMuxer`):** Extrai a faixa AAC de áudio diretamente do contêiner MP4 no próprio Android em menos de **0,3 segundos**, reduzindo o tamanho do arquivo de ~16 MB para apenas **~3 MB** sem re-codificação de áudio.
- **Capas Automáticas:** Baixa a imagem de capa em alta fidelidade e associa à faixa baixada na biblioteca do player.
- **Remoção de Formatos Obsoletos:** Remoção total de formatos WebM de baixa fidelidade (16 kbps e 52 kbps).

### 🖥️ Conversor Complementar para PC (Python + yt-dlp + Mutagen)
- Servidor HTTP local (`converter_server.py`) e interface gráfica amigável (`converter_gui.py`).
- Conversão rápida para MP3 (128 kbps e 192 kbps) e MP4 (720p HD) com incorporação automática de metadados e tags ID3 APIC.
- Inicialização facilitada com um clique através do script `iniciar_conversor.bat`.

---

## 📁 Estrutura do Projeto

```
AppMusic/
├── appmusic/               # Aplicativo Flutter para Android
│   ├── android/            # Código nativo Kotlin (MainActivity, DownloadManagerBridge)
│   ├── lib/                # Telas, modelos, serviços (AudioHandler, DownloadResolver, etc.)
│   └── test/               # Suíte completa de testes unitários automatizados
├── python_converter/       # Servidor e GUI em Python (yt-dlp, FFmpeg, Mutagen)
│   ├── converter.py
│   ├── converter_gui.py
│   ├── converter_server.py
│   └── iniciar_conversor.bat
├── AppMusic-APK/           # Diretório de geração do pacote APK
└── iniciar_conversor.bat   # Script raiz de inicialização rápida
```

---

## 🚀 Como Executar

### 1. Aplicativo Android (Flutter)
```bash
cd appmusic
flutter pub get
flutter run
```

Para gerar o APK:
```bash
cd appmusic
flutter build apk --debug
```

### 2. Conversor Python para PC (Opcional)
Execute o arquivo:
```cmd
iniciar_conversor.bat
```
Ou manualmente no terminal:
```bash
cd python_converter
pip install yt-dlp imageio-ffmpeg mutagen
python converter_gui.py
```

---

## 🏷️ Versão 0.2
- Versão do pacote: `0.2.0+2`
- Extração nativa de áudio AAC com demuxing (imune a Erro 403).
- Otimização do tamanho de músicas baixadas (~3 MB).
- Associação de capa oficial do YouTube para faixas baixadas.
- Limpeza de resíduos e formatos obsoletos.
