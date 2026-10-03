import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'compress_service.dart';

void main() => runApp(const ClearStatusApp());

class ClearStatusApp extends StatelessWidget {
  const ClearStatusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ClearStatus',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: Colors.green,
            brightness: Brightness.dark,
            useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = CompressService();
  final _picker = ImagePicker();
  StreamSubscription<double>? _sub;

  String? _inputPath;
  StatusPreset _preset = StatusPreset.balanced;
  int _res = 720;
  int _segment = 30;
  bool _split = true;
  bool _busy = false;
  double _progress = 0;
  String _stage = '';
  List<PartResult> _outputs = [];

  @override
  void initState() {
    super.initState();
    _sub = _service.progress.listen((p) => setState(() => _progress = p / 100));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) {
      setState(() {
        _inputPath = f.path;
        _outputs = [];
      });
    }
  }

  Future<void> _compress() async {
    if (_inputPath == null) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _outputs = [];
    });
    try {
      final r = await _service.run(
        _inputPath!,
        preset: _preset,
        shortSide: _res,
        split: _split,
        segmentSeconds: _segment,
        onPart: (d, t) => setState(() => _stage = 'Part $d of $t'),
      );
      setState(() => _outputs = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Compression failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(PartResult p) =>
      Share.shareXFiles([XFile(p.file.path, mimeType: 'video/mp4')]);

  Widget _chips<T>(String title, List<T> values, T selected,
      String Function(T) label, void Function(T) onTap) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text(title),
      Wrap(spacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            onSelected: _busy ? null : (_) => setState(() => onTap(v)),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final estMb = CompressService.estimateMb(_preset.mbps, _segment);
    final tooBig = estMb > CompressService.warnMb;
    return Scaffold(
      appBar: AppBar(title: const Text('ClearStatus')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Shrinks each part to a small, fixed size before upload so WhatsApp leaves it alone.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.video_library),
            label: Text(_inputPath == null ? 'Choose video' : 'Change video'),
          ),
          if (_inputPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_inputPath!.split('/').last,
                  overflow: TextOverflow.ellipsis),
            ),
          _chips<int>('Resolution', [540, 720, 1080], _res,
              (v) => '${v}p', (v) => _res = v),
          _chips<StatusPreset>('Quality', StatusPreset.values, _preset,
              (v) => '${v.label} ${v.mbps} Mbps', (v) => _preset = v),
          _chips<int>('Part length', [15, 30, 45, 60, 90], _segment,
              (v) => '${v}s', (v) => _segment = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Split into ${_segment}s parts'),
            subtitle: const Text('Off = only the first part is made'),
            value: _split,
            onChanged: _busy ? null : (v) => setState(() => _split = v),
          ),
          Text('Each part will be about $estMb MB.',
              style: TextStyle(color: tooBig ? Colors.orange : null)),
          if (tooBig)
            const Text(
                'Over ~16 MB, WhatsApp is likely to re-compress it. Use a shorter part or Compact quality.',
                style: TextStyle(color: Colors.orange)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (_busy || _inputPath == null) ? null : _compress,
            child: const Text('Compress'),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            Text(_stage),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
            TextButton(onPressed: _service.cancel, child: const Text('Cancel')),
          ],
          if (_outputs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Ready to post',
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _outputs.length; i++)
              ListTile(
                leading: const Icon(Icons.movie),
                title: Text('Part ${i + 1}'),
                subtitle: Text(
                    '${_outputs[i].width ?? '?'}x${_outputs[i].height ?? '?'} · ${_outputs[i].mb.toStringAsFixed(1)} MB · ${_outputs[i].mbps.toStringAsFixed(1)} Mbps${_outputs[i].untouched ? ' · original, already small' : ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => _share(_outputs[i]),
                ),
              ),
            const Text(
                "Tip: pick WhatsApp > My status. Don't trim or edit inside WhatsApp, as that re-encodes again."),
          ],
        ],
      ),
    );
  }
}
