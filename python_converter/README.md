# 🎵 AppMusic - Conversor YouTube para MP3 (Python + yt-dlp + FFmpeg)

Sistema completo de conversão e download de músicas do YouTube diretamente para **MP3** ou **Vídeo MP4** de alta fidelidade (128 kbps até 320 kbps), inspirado no repositório [DorianNaaji/Youtube-To-MP3-Converter](https://github.com/DorianNaaji/Youtube-To-MP3-Converter).

---

## ⚡ Como Usar (Mais Fácil)

Basta dar **duplo clique** no arquivo:
👉 **`iniciar_conversor.bat`** (na pasta raiz ou dentro de `python_converter/`)

Ele verifica as dependências e abre a interface gráfica imediatamente!

---

## 🖥️ Recursos da Interface Gráfica (`converter_gui.py`)

1. **Multi-Links**: Cole múltiplos links do YouTube de uma só vez (um por linha).
2. **Qualidade do MP3**:
   - `MP3 - 320 kbps (Máxima Fidelidade)`
   - `MP3 - 256 kbps (Alta Qualidade)`
   - `MP3 - 192 kbps (Recomendada)`
   - `MP3 - 128 kbps (Econômico)`
   - `MP4 - Vídeo Completo (Áudio + Vídeo)`
3. **Verificar Links**: Testa os links e mostra os títulos e artistas antes de iniciar.
4. **Abrir Pasta**: Abre diretamente a pasta `Desktop\ConvertedMp3` onde suas músicas são salvas com metadados e capas.
5. **Servidor Celular (Porta 5000)**: Inicia o servidor local para que o aplicativo **AppMusic** no seu celular baixe as músicas direto pelo seu computador sem nenhum erro 403!

---

## 📱 Como Conectar com o AppMusic no Celular

1. No computador, abra o conversor e clique em **"🌐 Iniciar Servidor Celular"**.
2. A tela mostrará o seu IP local (exemplo: `http://192.168.1.100:5000`).
3. No celular (conectado na mesma rede Wi-Fi), abra o **AppMusic** > **Configurações** > **Servidor Python (yt-dlp)** e digite esse endereço.
4. Pronto! Qualquer música consultada no AppMusic agora terá a opção:
   - `Áudio MP3 (yt-dlp · 320 kbps Máxima)`
   - `Áudio MP3 (yt-dlp · 192 kbps Padrão)`
   - `Vídeo MP4 (yt-dlp)`
   E baixará com **100% de sucesso**.
