import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverUrl = prefs.getString('python_converter_url');
    });
  }

  Future<void> _editServerUrl() async {
    final textController = TextEditingController(text: _serverUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Servidor Python (yt-dlp)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Caso execute o Conversor Python no seu computador, informe o endereço exibido na tela do conversor:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'URL do Servidor',
                hintText: 'Ex: http://192.168.1.100:5000',
                prefixIcon: Icon(Icons.computer_rounded),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Limpar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(textController.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      if (result.isEmpty) {
        await prefs.remove('python_converter_url');
        setState(() => _serverUrl = null);
      } else {
        await prefs.setString('python_converter_url', result);
        setState(() => _serverUrl = result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        Text('Preferências', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Tema escuro'),
            subtitle: const Text('Manter a interface escura por padrão'),
            value: controller.isDarkTheme,
            onChanged: (_) => controller.toggleTheme(),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.library_add_check_outlined),
            title: const Text('Atualizar biblioteca'),
            subtitle: const Text('Procurar músicas neste dispositivo'),
            trailing: controller.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: controller.isLoading ? null : controller.refreshLibrary,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.wifi_tethering_rounded),
            title: const Text('Servidor Python (yt-dlp)'),
            subtitle: Text(
              _serverUrl != null && _serverUrl!.isNotEmpty
                  ? 'Conectado em: $_serverUrl'
                  : 'Opcional · Conectar ao conversor no PC (porta 5000)',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _editServerUrl,
          ),
        ),
        if (controller.permissionDenied)
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Permissão de áudio'),
              subtitle: const Text(
                'Ajuste o acesso nas configurações do Android',
              ),
              onTap: openAppSettings,
            ),
          ),
        const SizedBox(height: 24),
        Text('Sobre', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.graphic_eq_rounded),
            title: const Text('AppMusic'),
            subtitle: Text(
              'Player offline · ${controller.tracks.length} músicas locais',
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'As músicas são reproduzidas diretamente do armazenamento do '
            'dispositivo. O aplicativo não usa streaming nem envia sua '
            'biblioteca para servidores.',
          ),
        ),
      ],
    );
  }
}
