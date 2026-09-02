import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../data/mock_data.dart';
import '../theme/tokens.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String _path = '/var/log';
  String? _preview;

  static const _quickPaths = ['/', '/home', '/etc', '/var/log', '/srv/docker'];

  List<String> get _crumbs {
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    return ['/', ...parts];
  }

  void _open(String crumb, int idx) {
    if (idx == 0) {
      setState(() => _path = '/');
      return;
    }
    final parts = _crumbs.sublist(1, idx + 1);
    setState(() => _path = '/${parts.join('/')}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final entries = dirs[_path] ?? const [];
    final wide = MediaQuery.of(context).size.width >= 760;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: const BoxDecoration(color: AxColors.s1, border: Border(bottom: BorderSide(color: AxColors.line))),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _crumbs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: GestureDetector(
                            onTap: () => _open(_crumbs[i], i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: i == _crumbs.length - 1 ? AxColors.s2 : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(_crumbs[i], style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: i == _crumbs.length - 1 ? AxColors.fg : AxColors.fg2)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => app.go(AxSection.terminal),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: AxColors.s2, borderRadius: BorderRadius.circular(AxRadius.pill), border: Border.all(color: AxColors.line)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_right_rounded, size: 14, color: AxColors.fg2),
                      const SizedBox(width: 5),
                      Text('Open in terminal', style: AxTextStyles.sans.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: AxColors.fg2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Container(
                  width: 196,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: const BoxDecoration(color: AxColors.s1, border: Border(right: BorderSide(color: AxColors.line))),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 7),
                          child: Text('QUICK JUMP', style: AxTextStyles.sans.copyWith(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AxColors.fg3)),
                        ),
                        for (final p in _quickPaths) _TreeRow(label: p, selected: p == _path, onTap: () => setState(() => _path = p)),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AxColors.line))),
                            child: const Row(
                              children: [
                                Expanded(flex: 3, child: _ColLabel('NAME')),
                                SizedBox(width: 14),
                                Expanded(child: _ColLabel('SIZE', alignEnd: true)),
                                SizedBox(width: 14),
                                Expanded(child: _ColLabel('PERMS')),
                                SizedBox(width: 14),
                                Expanded(child: _ColLabel('MODIFIED')),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, i) {
                                final f = entries[i];
                                return _FileRow(
                                  entry: f,
                                  onTap: () {
                                    if (f.kind == 'dir') {
                                      setState(() {
                                        _path = _path == '/' ? '/${f.name}' : '$_path/${f.name}';
                                        _preview = null;
                                      });
                                    } else {
                                      setState(() => _preview = f.name);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_preview != null) _PreviewPane(name: _preview!, onClose: () => setState(() => _preview = null)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  final bool alignEnd;
  const _ColLabel(this.text, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) => Text(text, textAlign: alignEnd ? TextAlign.right : TextAlign.left, style: AxTextStyles.label);
}

class _TreeRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TreeRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: selected ? AxColors.s2 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 12, color: selected ? AxColors.accent : AxColors.fg3),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: selected ? AxColors.fg : AxColors.fg2), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final dynamic entry;
  final VoidCallback onTap;
  const _FileRow({required this.entry, required this.onTap});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.entry;
    final icon = f.kind == 'dir' ? Icons.folder_outlined : (f.kind == 'log' ? Icons.article_outlined : Icons.insert_drive_file_outlined);
    final iconColor = f.kind == 'dir' ? AxColors.info : (f.kind == 'log' ? AxColors.warn : AxColors.fg3);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          decoration: BoxDecoration(color: _hover ? AxColors.s2 : Colors.transparent, border: const Border(bottom: BorderSide(color: Color(0x0AE8F0E6)))),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: iconColor),
                    const SizedBox(width: 9),
                    Expanded(child: Text(f.name, style: AxTextStyles.mono.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(f.size, textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg2))),
              const SizedBox(width: 14),
              Expanded(child: Text(f.perms, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3))),
              const SizedBox(width: 14),
              Expanded(child: Text(f.mtime, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  final String name;
  final VoidCallback onClose;
  const _PreviewPane({required this.name, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final lines = filePreviews[name] ?? const ['(no preview available for this file type)'];
    return Container(
      decoration: const BoxDecoration(color: AxColors.s1, border: Border(top: BorderSide(color: AxColors.line2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              children: [
                Text(name, style: AxTextStyles.mono.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500)),
                const SizedBox(width: 9),
                Text('${lines.length} lines', style: AxTextStyles.mono.copyWith(fontSize: 10, color: AxColors.fg3)),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close_rounded, size: 16, color: AxColors.fg3),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 26, child: Text('${i + 1}', textAlign: TextAlign.right, style: AxTextStyles.mono.copyWith(fontSize: 11, color: AxColors.fg3.withValues(alpha: 0.55)))),
                          const SizedBox(width: 12),
                          Expanded(child: Text(lines[i], style: AxTextStyles.mono.copyWith(fontSize: 11, height: 1.6))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
