import 'dart:developer' as commonPrint;
import 'dart:io';
import 'dart:convert';

import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

import '../../common/path.dart';

// Simple provider for SNI history - using standard Notifier pattern
class SniHistory extends Notifier<List<String>> {
  @override
  List<String> build() {
    _loadHistory();
    return [];
  }

  Future<void> _loadHistory() async {
    try {
      final historyPath = await _getHistoryPath();
      final file = File(historyPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        state = jsonList.cast<String>();
      }
    } catch (e) {
      commonPrint.log('Error loading SNI history: $e');
    }
  }

  Future<String> _getHistoryPath() async {
    final homeDir = await appPath.homeDirPath;
    return join(homeDir, 'sni_history.json');
  }

  Future<void> addSni(String sni) async {
    if (sni.isEmpty) return;

    // Remove if already exists and add to top
    final newList = state.where((item) => item != sni).toList();
    newList.insert(0, sni);

    // Keep only last 10 SNIs
    if (newList.length > 10) {
      newList.removeRange(10, newList.length);
    }

    state = newList;
    await _saveHistory();
  }

  Future<void> removeSni(String sni) async {
    state = state.where((item) => item != sni).toList();
    await _saveHistory();
  }

  Future<void> _saveHistory() async {
    try {
      final historyPath = await _getHistoryPath();
      final file = File(historyPath);
      await file.writeAsString(json.encode(state));
    } catch (e) {
      commonPrint.log('Error saving SNI history: $e');
    }
  }
}

// Provider definition
final sniHistoryProvider = NotifierProvider<SniHistory, List<String>>(() {
  return SniHistory();
});

class SniOverrideDialog extends ConsumerStatefulWidget {
  final String? specificProxyName;
  final String currentSni;

  const SniOverrideDialog({
    super.key,
    this.specificProxyName,
    required this.currentSni,
  });

  @override
  ConsumerState<SniOverrideDialog> createState() => _SniOverrideDialogState();
}

class _SniOverrideDialogState extends ConsumerState<SniOverrideDialog> {
  final TextEditingController _sniController = TextEditingController();
  final FocusNode _sniFocusNode = FocusNode();
  bool _overrideAllProxies = true;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _sniController.text = widget.currentSni;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sniFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _sniController.dispose();
    _sniFocusNode.dispose();
    super.dispose();
  }

  Future<void> _applySniOverride() async {
    final newSni = _sniController.text.trim();

    if (_overrideAllProxies) {
      await _overrideSniForAllProxies(newSni);
    } else if (widget.specificProxyName != null) {
      await _overrideSniForSpecificProxy(widget.specificProxyName!, newSni);
    }

    // Add to history if not empty
    if (newSni.isNotEmpty) {
      await ref.read(sniHistoryProvider.notifier).addSni(newSni);
    }

    if (mounted) {
      Navigator.of(context as BuildContext).pop(true);
    }
  }

  Future<void> _overrideSniForAllProxies(String newSni) async {
    try {
      final currentProfile = ref.read(currentProfileProvider);
      if (currentProfile == null) return;

      final profilePath = await appPath.getProfilePath(currentProfile.id);
      final file = File(profilePath);

      if (!await file.exists()) return;

      final content = await file.readAsString();
      final lines = content.split('\n');
      final newLines = <String>[];

      bool inProxiesSection = false;
      bool inProxyBlock = false;
      List<String> currentProxyBlock = [];
      int proxiesUpdated = 0;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmedLine = line.trim();

        if (trimmedLine == 'proxies:') {
          inProxiesSection = true;
          inProxyBlock = false;
          newLines.add(line);
          continue;
        }

        if (inProxiesSection && trimmedLine.isNotEmpty && !line.startsWith(' ')) {
          if (inProxyBlock) {
            _addOrUpdateSniInProxyBlock(currentProxyBlock, newSni);
            newLines.addAll(currentProxyBlock);
            currentProxyBlock.clear();
            proxiesUpdated++;
          }
          inProxiesSection = false;
          inProxyBlock = false;
          newLines.add(line);
          continue;
        }

        if (inProxiesSection) {
          if (trimmedLine.startsWith('- name:')) {
            if (inProxyBlock) {
              _addOrUpdateSniInProxyBlock(currentProxyBlock, newSni);
              newLines.addAll(currentProxyBlock);
              currentProxyBlock.clear();
              proxiesUpdated++;
            }

            currentProxyBlock = [line];
            inProxyBlock = true;
          } else if (inProxyBlock) {
            currentProxyBlock.add(line);

            if (i + 1 < lines.length) {
              final nextLine = lines[i + 1].trim();
              if (nextLine.isEmpty || nextLine.startsWith('- name:')) {
                _addOrUpdateSniInProxyBlock(currentProxyBlock, newSni);
                newLines.addAll(currentProxyBlock);
                currentProxyBlock.clear();
                inProxyBlock = false;
                proxiesUpdated++;
              }
            }
          } else {
            newLines.add(line);
          }
        } else {
          newLines.add(line);
        }
      }

      if (inProxyBlock) {
        _addOrUpdateSniInProxyBlock(currentProxyBlock, newSni);
        newLines.addAll(currentProxyBlock);
        proxiesUpdated++;
      }

      final newContent = newLines.join('\n');
      await file.writeAsString(newContent);

      await ref.read(currentProfileProvider)?.checkAndUpdate();
      await globalState.appController.applyProfile(silence: true);

      globalState.showNotifier('SNI updated for $proxiesUpdated proxies');

    } catch (e) {
      commonPrint.log('Error updating SNI for all proxies: $e');
      globalState.showNotifier('Failed to update SNI: $e');
    }
  }

  void _addOrUpdateSniInProxyBlock(List<String> proxyBlock, String newSni) {
    if (newSni.isEmpty) {
      proxyBlock.removeWhere((line) => line.trim().startsWith('sni:'));
      return;
    }

    bool sniFound = false;
    for (int i = 0; i < proxyBlock.length; i++) {
      if (proxyBlock[i].trim().startsWith('sni:')) {
        proxyBlock[i] = '    sni: ${_escapeYamlValue(newSni)}';
        sniFound = true;
        break;
      }
    }

    if (!sniFound && newSni.isNotEmpty) {
      int insertIndex = _findSniInsertPosition(proxyBlock);
      proxyBlock.insert(insertIndex, '    sni: ${_escapeYamlValue(newSni)}');
    }
  }

  int _findSniInsertPosition(List<String> proxyBlock) {
    final basicFields = ['name:', 'type:', 'server:', 'port:'];
    int lastBasicFieldIndex = -1;

    for (int i = 0; i < proxyBlock.length; i++) {
      final line = proxyBlock[i].trim();
      for (final field in basicFields) {
        if (line.startsWith(field)) {
          lastBasicFieldIndex = i;
          break;
        }
      }
    }

    return lastBasicFieldIndex + 1;
  }

  Future<void> _overrideSniForSpecificProxy(String proxyName, String newSni) async {
    try {
      final currentProfile = ref.read(currentProfileProvider);
      if (currentProfile == null) return;

      final profilePath = await appPath.getProfilePath(currentProfile.id);
      final file = File(profilePath);

      if (!await file.exists()) return;

      final content = await file.readAsString();
      final lines = content.split('\n');
      final newLines = <String>[];

      bool inTargetProxy = false;
      bool inProxyBlock = false;
      List<String> currentProxyBlock = [];

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmedLine = line.trim();

        if (trimmedLine == 'proxies:') {
          inTargetProxy = false;
          inProxyBlock = false;
          newLines.add(line);
          continue;
        }

        if (!inTargetProxy && trimmedLine.startsWith('- name:')) {
          final namePart = line.split('name:').last.trim();
          final currentProxyName = _extractProxyName(namePart);

          if (currentProxyName == proxyName) {
            inTargetProxy = true;
            inProxyBlock = true;
            currentProxyBlock = [line];
            continue;
          }
        }

        if (inTargetProxy && inProxyBlock) {
          currentProxyBlock.add(line);

          if (i + 1 < lines.length) {
            final nextLine = lines[i + 1].trim();
            if (nextLine.isEmpty || nextLine.startsWith('- name:')) {
              _addOrUpdateSniInProxyBlock(currentProxyBlock, newSni);
              newLines.addAll(currentProxyBlock);
              currentProxyBlock.clear();
              inTargetProxy = false;
              inProxyBlock = false;
            }
          }
        } else {
          newLines.add(line);
        }
      }

      final newContent = newLines.join('\n');
      await file.writeAsString(newContent);

      await ref.read(currentProfileProvider)?.checkAndUpdate();
      await globalState.appController.applyProfile(silence: true);

      globalState.showNotifier('SNI updated for $proxyName');

    } catch (e) {
      commonPrint.log('Error updating SNI for specific proxy: $e');
      globalState.showNotifier('Failed to update SNI: $e');
    }
  }

  String _extractProxyName(String nameLine) {
    var name = nameLine.replaceAll('"', '').replaceAll("'", '').trim();
    try {
      name = Uri.decodeComponent(name);
    } catch (e) {
      name = name.replaceAll('%20', ' ');
    }
    return name;
  }

  String _escapeYamlValue(String value) {
    if (value.isEmpty) return '""';
    if (_requiresQuotes(value)) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return value;
  }

  bool _requiresQuotes(String value) {
    return value.contains(':') ||
        value.contains(' ') ||
        value.contains('"') ||
        value.contains("'") ||
        value.startsWith('[') ||
        value.startsWith('{');
  }

  @override
  Widget build(BuildContext context) {
    final sniHistory = ref.watch(sniHistoryProvider);

    return AlertDialog(
      title: Text(widget.specificProxyName != null
          ? 'Override SNI for ${widget.specificProxyName}'
          : 'Override SNI for All Proxies'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.specificProxyName != null) ...[
              CheckboxListTile(
                title: const Text('Apply to all proxies'),
                value: _overrideAllProxies,
                onChanged: (value) {
                  setState(() {
                    _overrideAllProxies = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Enter new Server Name Indication (SNI):',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sniController,
              focusNode: _sniFocusNode,
              decoration: InputDecoration(
                hintText: 'e.g., google.com, cloudflare.com',
                border: const OutlineInputBorder(),
                labelText: 'SNI',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_sniController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _sniController.clear();
                          });
                        },
                      ),
                    IconButton(
                      icon: Icon(
                        _showHistory ? Icons.history : Icons.history_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _showHistory = !_showHistory;
                        });
                      },
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _applySniOverride(),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave empty to remove SNI override',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_overrideAllProxies && widget.specificProxyName != null) ...[
              const SizedBox(height: 8),
              Text(
                'This will override SNI for ALL proxies in the profile',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            // SNI History Section
            if (_showHistory && sniHistory.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Recent SNIs:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sniHistory.length,
                  itemBuilder: (context, index) {
                    final sni = sniHistory[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(sni),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, size: 20),
                              onPressed: () {
                                setState(() {
                                  _sniController.text = sni;
                                });
                              },
                              tooltip: 'Use this SNI',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              onPressed: () {
                                ref.read(sniHistoryProvider.notifier).removeSni(sni);
                              },
                              tooltip: 'Remove from history',
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _sniController.text = sni;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _applySniOverride,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}