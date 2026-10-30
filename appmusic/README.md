# AppMusic

[![Version](https://img.shields.io/badge/version-v0.1-purple)](https://github.com/JoaoNicolasFreitas/Appmusic/releases/tag/v0.1)

Player Flutter de músicas locais para Android. A biblioteca é consultada no
MediaStore e a reprodução funciona a partir dos arquivos disponíveis no
dispositivo, sem streaming ou conta de usuário.

## Versão 0.1

Esta versão inicial inclui biblioteca local, reprodução em segundo plano,
playlists, favoritos, busca e exclusão autorizada pelo Android.

## Recursos

- Biblioteca local com busca por título/artista/álbum, ordenação e capas.
- Reprodução em segundo plano com fila, notificação e controles de mídia.
- Reprodução aleatória, repetição, avanço e busca por trecho.
- Favoritos e playlists salvos localmente.
- Exclusão de faixa com confirmação no aplicativo e, quando exigido, pelo
  diálogo de autorização do Android.
- Tema escuro padrão e atualização manual da biblioteca.

O aplicativo não baixa músicas de links do YouTube. Os arquivos de áudio devem
ser copiados para o dispositivo por meios autorizados; depois disso, use
**Atualizar biblioteca** para encontrá-los.

## Permissões Android

- `READ_MEDIA_AUDIO` em Android 13 ou superior.
- `READ_EXTERNAL_STORAGE` em Android 12 ou anterior.
- `WRITE_EXTERNAL_STORAGE` somente até Android 10, para exclusão em versões
  antigas.
- Serviço de reprodução em primeiro plano para controles de mídia em segundo
  plano.

As permissões de mídia são solicitadas quando o usuário abre/atualiza a
biblioteca. O aplicativo não pede acesso a fotos, localização ou internet.

## Executar e validar

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

O APK de depuração é gerado em
`build\app\outputs\flutter-apk\app-debug.apk`.

Para instalar com um dispositivo Android conectado e depuração USB habilitada:

```powershell
flutter install
```

Também é possível copiar o APK para o celular e abri-lo. No primeiro uso,
conceda acesso a arquivos de áudio, coloque músicas no armazenamento do
dispositivo e atualize a biblioteca.
