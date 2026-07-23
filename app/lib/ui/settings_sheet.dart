/// Einstellungsdialog mit drei Tabs: Direktmodus (Modifier-Mapping,
/// Alt-Zeichenliste, Umschalt-Taste), Geräteliste (Name/Host/Port/Token je
/// Gerät) und Snippets (max. 9 Textbausteine). Gibt das Gesamtergebnis
/// zurück oder `null` bei Abbruch — persistiert wird beim Aufrufer.
library;

import 'package:flutter/material.dart';

import '../config/models.dart';
import '../dictusb/keymap.dart';

class SettingsResult {
  final DirectSettings direct;
  final List<Device> devices;
  final List<Snippet> snippets;
  const SettingsResult({
    required this.direct,
    required this.devices,
    required this.snippets,
  });
}

Future<SettingsResult?> showSettingsSheet(
  BuildContext context, {
  required DirectSettings direct,
  required List<Device> devices,
  required List<Snippet> snippets,
  required bool isMacOS,
}) =>
    showDialog<SettingsResult>(
      context: context,
      builder: (_) => _SettingsDialog(
        direct: direct,
        devices: devices,
        snippets: snippets,
        isMacOS: isMacOS,
      ),
    );

const int maxSnippets = 9;

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.direct,
    required this.devices,
    required this.snippets,
    required this.isMacOS,
  });

  final DirectSettings direct;
  final List<Device> devices;
  final List<Snippet> snippets;
  final bool isMacOS;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late TargetMod _ctrlTo = widget.direct.ctrlTo;
  late TargetMod _altTo = widget.direct.altTo;
  late TargetMod _metaTo = widget.direct.metaTo;
  late String _toggleKey = widget.direct.toggleKey;
  late final TextEditingController _altChars =
      TextEditingController(text: widget.direct.altChars);
  late final List<Device> _devices = List.of(widget.devices);
  late final List<Snippet> _snippets = List.of(widget.snippets);

  static const _modLabels = {
    TargetMod.ctrl: 'Strg',
    TargetMod.alt: 'Alt',
    TargetMod.win: 'Win',
  };

  @override
  void dispose() {
    _altChars.dispose();
    super.dispose();
  }

  void _resetDirect() {
    final d = DirectSettings.defaultsFor(isMacOS: widget.isMacOS);
    setState(() {
      _ctrlTo = d.ctrlTo;
      _altTo = d.altTo;
      _metaTo = d.metaTo;
      _toggleKey = d.toggleKey;
      _altChars.text = d.altChars;
    });
  }

  Widget _modDropdown(
    String label,
    TargetMod value,
    ValueChanged<TargetMod> onChanged,
  ) =>
      DropdownButtonFormField<TargetMod>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final m in TargetMod.values)
            DropdownMenuItem(value: m, child: Text(_modLabels[m]!)),
        ],
        onChanged: (m) => m == null ? null : onChanged(m),
      );

  Widget _directTab(BuildContext context) {
    final mac = widget.isMacOS;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modDropdown(
            mac ? 'control ⌃ sendet als …' : 'Strg sendet als …',
            _ctrlTo,
            (m) => setState(() => _ctrlTo = m),
          ),
          const SizedBox(height: 12),
          _modDropdown(
            mac ? 'option ⌥ sendet als …' : 'Alt sendet als …',
            _altTo,
            (m) => setState(() => _altTo = m),
          ),
          const SizedBox(height: 12),
          _modDropdown(
            mac ? 'command ⌘ sendet als …' : 'Win sendet als …',
            _metaTo,
            (m) => setState(() => _metaTo = m),
          ),
          const SizedBox(height: 8),
          Text(
            'Shift bleibt immer Shift.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _altChars,
            decoration: const InputDecoration(
              labelText: 'Alt-Sonderzeichen direkt tippen',
              helperText: 'Diese mit Alt/Option erzeugten Zeichen werden '
                  'als Text gesendet statt als Tastenkombination.',
              helperMaxLines: 3,
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _toggleKey,
            decoration: const InputDecoration(
              labelText: 'Umschalt-Taste Block/Direkt',
              isDense: true,
            ),
            items: [
              for (final name in fKeyByName.keys)
                DropdownMenuItem(
                  value: name,
                  child: Text(name.toUpperCase()),
                ),
            ],
            onChanged: (v) =>
                v == null ? null : setState(() => _toggleKey = v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _resetDirect,
              child: const Text('Zurücksetzen'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDevice(int? index) async {
    // Token vorbelegen: beim Anlegen vom ersten Gerät übernehmen (beide
    // Geräte teilen sich heute real dasselbe Token).
    final initial = index != null
        ? _devices[index]
        : Device(
            name: 'Gerät ${_devices.length + 1}',
            host: '',
            port: 8080,
            token: _devices.isEmpty ? '' : _devices.first.token,
          );
    final result = await showDialog<Device>(
      context: context,
      builder: (_) => _DeviceDialog(initial: initial, isNew: index == null),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _devices.add(result);
      } else {
        _devices[index] = result;
      }
    });
  }

  Widget _devicesTab(BuildContext context) => Column(
        children: [
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text('Noch kein Gerät angelegt.'))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (_, i) {
                      final d = _devices[i];
                      return ListTile(
                        dense: true,
                        title: Text(d.name),
                        subtitle: Text('${d.host}:${d.port}'),
                        onTap: () => _editDevice(i),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Löschen',
                          onPressed: () =>
                              setState(() => _devices.removeAt(i)),
                        ),
                      );
                    },
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editDevice(null),
              icon: const Icon(Icons.add),
              label: const Text('Gerät hinzufügen'),
            ),
          ),
        ],
      );

  Future<void> _editSnippet(int? index) async {
    final initial = index != null
        ? _snippets[index]
        : const Snippet(label: '', text: '');
    final result = await showDialog<Snippet>(
      context: context,
      builder: (_) => _SnippetDialog(initial: initial, isNew: index == null),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _snippets.add(result);
      } else {
        _snippets[index] = result;
      }
    });
  }

  Widget _snippetsTab(BuildContext context) => Column(
        children: [
          Expanded(
            child: _snippets.isEmpty
                ? const Center(
                    child: Text('Noch keine Textbausteine angelegt.'),
                  )
                : ListView.builder(
                    itemCount: _snippets.length,
                    itemBuilder: (_, i) {
                      final s = _snippets[i];
                      return ListTile(
                        dense: true,
                        leading: Text('${i + 1}'),
                        title: Text(s.label),
                        subtitle: Text(
                          s.text.replaceAll('\n', '⏎'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _editSnippet(i),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Löschen',
                          onPressed: () =>
                              setState(() => _snippets.removeAt(i)),
                        ),
                      );
                    },
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _snippets.length >= maxSnippets
                  ? null
                  : () => _editSnippet(null),
              icon: const Icon(Icons.add),
              label: Text(_snippets.length >= maxSnippets
                  ? 'Maximal $maxSnippets Bausteine'
                  : 'Baustein hinzufügen'),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Einstellungen'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Direktmodus'),
                  Tab(text: 'Geräte'),
                  Tab(text: 'Snippets'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _directTab(context),
                    _devicesTab(context),
                    _snippetsTab(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(SettingsResult(
            direct: DirectSettings(
              ctrlTo: _ctrlTo,
              altTo: _altTo,
              metaTo: _metaTo,
              altChars: _altChars.text,
              toggleKey: _toggleKey,
            ),
            devices: List.unmodifiable(_devices),
            snippets: List.unmodifiable(_snippets),
          )),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _DeviceDialog extends StatefulWidget {
  const _DeviceDialog({required this.initial, required this.isNew});

  final Device initial;
  final bool isNew;

  @override
  State<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<_DeviceDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.name);
  late final TextEditingController _host =
      TextEditingController(text: widget.initial.host);
  late final TextEditingController _port =
      TextEditingController(text: '${widget.initial.port}');
  late final TextEditingController _token =
      TextEditingController(text: widget.initial.token);

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.isNew ? 'Gerät hinzufügen' : 'Gerät bearbeiten'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'Host/IP',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(Device(
              name: _name.text.trim().isEmpty
                  ? _host.text.trim()
                  : _name.text.trim(),
              host: _host.text.trim(),
              port: int.tryParse(_port.text.trim()) ?? 8080,
              token: _token.text,
            )),
            child: const Text('Übernehmen'),
          ),
        ],
      );
}

class _SnippetDialog extends StatefulWidget {
  const _SnippetDialog({required this.initial, required this.isNew});

  final Snippet initial;
  final bool isNew;

  @override
  State<_SnippetDialog> createState() => _SnippetDialogState();
}

class _SnippetDialogState extends State<_SnippetDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.initial.label);
  late final TextEditingController _text =
      TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _label.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.isNew ? 'Baustein hinzufügen' : 'Baustein bearbeiten',
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Beschriftung',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(Snippet(
              label: _label.text.trim().isEmpty
                  ? (_text.text.split('\n').first.length > 12
                      ? _text.text.split('\n').first.substring(0, 12)
                      : _text.text.split('\n').first)
                  : _label.text.trim(),
              text: _text.text,
            )),
            child: const Text('Übernehmen'),
          ),
        ],
      );
}
