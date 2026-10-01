import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_compress/video_compress.dart';
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

  String? _inputPath;
  StatusPreset _preset = StatusPreset.hd720;
  int _segment = 30;
  bool _split = true;
  bool _busy = false;
  double _progress = 0;
  String _stage = '';
  List<File> _outputs = [];
  Subscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = VideoCompress.compressProgress$
        .subscribe((p) => setState(() => _progress = p / 100));
  }

  @override
  void dispose() {
    _sub?.unsubscribe();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) setState(() {
      _inputPath = f.path;
      _outputs = [];
    });
  }

  Future<void> _compress() async {
    if (_inputPath == null) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _outputs = [];
    });
    try {
      final files = await _service.run(
        _inputPath!,
        preset: _preset,
        split: _split,
        segmentSeconds: _segment,
        onSegment: (d, t) => setState(() => _stage = 'Part $d of $t'),
      );
      setState(() => _outputs = files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Compression failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(File f) =>
      Share.shareXFiles([XFile(f.path, mimeType: 'video/mp4')]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ClearStatus')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Compress before you post so WhatsApp re-encodes gently.',
              style: Theme.of(context).textTheme.bodyMedium),
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
          const SizedBox(height: 16),
          DropdownButtonFormField<StatusPreset>(
            value: _preset,
            decoration: const InputDecoration(
                labelText: 'Quality', border: OutlineInputBorder()),
            items: [
              for (final p in StatusPreset.values)
                DropdownMenuItem(value: p, child: Text(p.label))
            ],
            onChanged: _busy ? null : (v) => setState(() => _preset = v!),
          ),
          const SizedBox(height: 8),
          const Text('Part length'),
          Wrap(
            spacing: 8,
            children: [
              for (final sec in [15, 30, 45, 60, 90])
                ChoiceChip(
                  label: Text('${sec}s'),
                  selected: _segment == sec,
                  onSelected: _busy ? null : (_) => setState(() => _segment = sec),
                ),
            ],
          ),
          SwitchListTile(
            title: Text('Split into ${_segment}s parts'),
            subtitle: const Text('Off = only the first part is made'),
            value: _split,
            onChanged: _busy ? null : (v) => setState(() => _split = v),
          ),
          const SizedBox(height: 8),
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
            Text('Ready to post', style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _outputs.length; i++)
              ListTile(
                leading: const Icon(Icons.movie),
                title: Text('Part ${i + 1}'),
                subtitle: Text(
                    '${(_outputs[i].lengthSync() / 1048576).toStringAsFixed(1)} MB'),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => _share(_outputs[i]),
                ),
              ),
            if (_outputs.any((f) => f.lengthSync() > 16 * 1048576))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Some parts are over 16 MB, so WhatsApp will likely re-compress them and blur them. Try 540p or a shorter part length.',
                    style: TextStyle(color: Colors.orange)),
              ),
            const Text(
                'Tip: choose WhatsApp > My status. Don\'t trim or edit inside WhatsApp, as that re-encodes again.'),
          ],
        ],
      ),
    );
  }
}
