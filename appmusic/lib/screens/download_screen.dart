import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/audio_track.dart';
import '../models/download_job.dart';
import '../models/download_preview.dart';
import '../providers/app_controller.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  bool _submitting = false;
  bool _resolving = false;
  DownloadPreview? _preview;
  DownloadAudioOption? _selectedOption;

  @override
  void initState() {
    super.initState();
    _offerClipboardLink();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = widget.controller.downloadService;
    return AnimatedBuilder(
      animation: downloads,
      builder: (context, _) {
        final jobs = downloads.jobs;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Text('Nova música', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autofillHints: const [AutofillHints.url],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Link ou ID do vídeo',
                        hintText: 'Cole o link do YouTube ou arquivo direto',
                        prefixIcon: const Icon(Icons.link_rounded),
                        helperText:
                            'Vídeos públicos do YouTube (ou ID) ou links diretos de áudio.',
                        suffixIcon: IconButton(
                          tooltip: 'Colar link',
                          onPressed: _pasteLink,
                          icon: const Icon(Icons.paste_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Título personalizado (opcional)',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_preview != null) _PreviewCard(preview: _preview!),
                    if (_preview?.options.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedOption?.id,
                        decoration: const InputDecoration(
                          labelText: 'Formato / Resolução',
                        ),
                        items: _preview!.options
                            .map(
                              (option) => DropdownMenuItem(
                                value: option.id,
                                child: Text(
                                  option.label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (id) => setState(() {
                          _selectedOption = _preview!.options
                              .where((option) => option.id == id)
                              .firstOrNull;
                        }),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _submitting || _resolving
                            ? null
                            : _preview == null
                            ? _resolve
                            : _addDownload,
                        icon: _submitting || _resolving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _preview == null
                                    ? Icons.search_rounded
                                    : Icons.download_rounded,
                              ),
                        label: Text(
                          _preview == null ? 'Consultar link' : 'Baixar agora',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Fila e histórico',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed:
                      jobs.any(
                        (job) => job.status == DownloadJobStatus.completed,
                      )
                      ? downloads.clearCompleted
                      : null,
                  child: const Text('Limpar concluídos'),
                ),
              ],
            ),
            if (jobs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhum download realizado.'),
                ),
              )
            else
              for (final job in jobs.reversed)
                _DownloadTile(
                  job: job,
                  controller: widget.controller,
                  onCancel: () => downloads.cancel(job.id),
                  onRetry: () => downloads.retry(job.id),
                  onRemove: () => downloads.remove(job.id),
                ),
          ],
        );
      },
    );
  }

  Future<void> _resolve() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma URL do YouTube ou link direto.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _resolving = true;
      _preview = null;
      _selectedOption = null;
    });
    try {
      final preview = await widget.controller.downloadService.resolve(text);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _selectedOption = preview.options.firstOrNull;
      });
    } catch (error) {
      if (!mounted) return;
      var message = error.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      } else if (message.startsWith('StateError: ')) {
        message = message.substring(12);
      } else if (message.startsWith('ArgumentError: ')) {
        message = message.substring(15);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _addDownload() async {
    final option = _selectedOption;
    final preview = _preview;
    if (option == null || preview == null) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.downloadService.enqueue(
        preview.sourceUrl,
        option,
        title: _titleController.text.trim().isEmpty
            ? preview.title
            : _titleController.text,
        artist: preview.artist,
        artworkUrl: preview.artworkUrl,
      );
      _urlController.clear();
      _titleController.clear();
      setState(() {
        _preview = null;
        _selectedOption = null;
      });
    } catch (error) {
      if (!mounted) return;
      var message = error.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      } else if (message.startsWith('StateError: ')) {
        message = message.substring(12);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _offerClipboardLink() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final value = clipboard?.text?.trim() ?? '';
    final resolver = widget.controller.downloadService;
    if (value.isEmpty || !resolver.supportsSource(value) || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Um link compatível foi encontrado na área de transferência.',
        ),
        action: SnackBarAction(
          label: 'Colar',
          onPressed: () => _urlController.text = value,
        ),
      ),
    );
  }

  Future<void> _pasteLink() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final value = clipboard?.text?.trim() ?? '';
    if (value.isNotEmpty) _urlController.text = value;
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final DownloadPreview preview;

  @override
  Widget build(BuildContext context) {
    final duration = preview.duration;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: preview.artworkUrl == null
                  ? const SizedBox(
                      width: 92,
                      height: 92,
                      child: Icon(Icons.music_note_rounded),
                    )
                  : Image.network(
                      preview.artworkUrl!,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                        width: 92,
                        height: 92,
                        child: Icon(Icons.music_note_rounded),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (preview.artist != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (duration != null) ...[
                    const SizedBox(height: 6),
                    Text(_formatDuration(duration)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.job,
    required this.controller,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  final DownloadJob job;
  final AppController controller;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (job.status) {
      DownloadJobStatus.queued => 'Na fila',
      DownloadJobStatus.running => 'Baixando',
      DownloadJobStatus.paused => 'Pausado',
      DownloadJobStatus.completed => 'Concluído',
      DownloadJobStatus.failed => 'Falhou',
      DownloadJobStatus.cancelled => 'Cancelado',
    };
    final canCancel =
        job.status == DownloadJobStatus.running ||
        job.status == DownloadJobStatus.queued;
    final canRetry =
        job.status == DownloadJobStatus.failed ||
        job.status == DownloadJobStatus.cancelled;
    final canPlay =
        job.status == DownloadJobStatus.completed && job.mediaId != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (canPlay)
                  IconButton(
                    tooltip: 'Reproduzir',
                    onPressed: () => _play(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                if (canRetry)
                  IconButton(
                    tooltip: 'Tentar novamente',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                if (canCancel)
                  IconButton(
                    tooltip: 'Cancelar',
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  IconButton(
                    tooltip: 'Excluir do histórico',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            if (job.status == DownloadJobStatus.running ||
                job.status == DownloadJobStatus.paused) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: job.progress),
              const SizedBox(height: 6),
              Text(
                _progressText(job),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (job.error?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  job.error!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _play(BuildContext context) async {
    var track = _findTrack(controller.tracks);
    if (track == null) {
      await controller.refreshLibrary();
      track = _findTrack(controller.tracks);
      if (track == null) return;
    }
    await controller.playTrack(track);
  }

  AudioTrack? _findTrack(List<AudioTrack> tracks) {
    for (final track in tracks) {
      if (track.id == job.mediaId) return track;
    }
    return null;
  }

  String _progressText(DownloadJob job) {
    final downloaded = _formatBytes(job.bytesDownloaded);
    if (job.totalBytes == null) return downloaded;
    final total = _formatBytes(job.totalBytes!);
    final percent = (job.progress * 100).toStringAsFixed(0);
    final speed = job.speedBytesPerSecond > 0
        ? ' · ${_formatBytes(job.speedBytesPerSecond)}/s'
        : '';
    final remaining = job.remainingSeconds;
    final eta = remaining == null
        ? ''
        : ' · ${_formatEta(Duration(seconds: remaining))} restante';
    return '$downloaded / $total · $percent%$speed$eta';
  }

  String _formatEta(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
