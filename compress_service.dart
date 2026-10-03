import 'dart:io';
import 'dart:math';
import 'package:light_compressor_v2/light_compressor_v2.dart';

/// Video bitrate target. The plugin's target-size mode has a 2 Mbps floor.
enum StatusPreset {
  compact('Compact', 2.0),
  balanced('Balanced', 2.5),
  high('High', 3.5);

  const StatusPreset(this.label, this.mbps);
  final String label;
  final double mbps;
}

class PartResult {
  PartResult(this.file, this.width, this.height, this.mb, this.mbps,
      {this.untouched = false});
  final bool untouched;
  final File file;
  final int? width, height;
  final double mb, mbps;
}

class CompressService {
  final _c = LightCompressor();
  Stream<double> get progress => _c.onProgressUpdated;

  static const warnMb = 16;

  /// Estimated size of one part, in MB (video + ~96 kbps audio).
  static int estimateMb(double videoMbps, int seconds) =>
      (seconds * (videoMbps + 0.1) / 8).ceil();

  static int _even(double v) => max(2, (v / 2).round() * 2);

  Future<Result> _encode(String path, int w, int h, int mb, VideoEdit? edit,
      String name) {
    return _c.compressVideo(
      path: path,
      videoQuality: VideoQuality.high,
      isMinBitrateCheckEnabled: false,
      video: Video(
        videoName: name,
        videoWidth: w,
        videoHeight: h,
        targetSizeMb: mb,
        twoPass: true,
        videoFps: 30,
      ),
      audio: const AudioConfig(bitrate: 96000),
      edit: edit,
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
    );
  }

  Future<List<PartResult>> run(
    String path, {
    required StatusPreset preset,
    required int shortSide,
    required bool split,
    required int segmentSeconds,
    void Function(int done, int total)? onPart,
  }) async {
    final info = await _c.getMediaInfo(path);
    final dw = (info.displayWidth ?? info.width ?? 720).toDouble();
    final dh = (info.displayHeight ?? info.height ?? 1280).toDouble();
    final totalMs = info.duration?.inMilliseconds ?? 0;
    final trimming = totalMs > segmentSeconds * 1000;
    final parts = (split && trimming) ? (totalMs / (segmentSeconds * 1000)).ceil() : 1;

    // Never upscale; keep aspect ratio; even dimensions.
    final scale = min(1.0, shortSide / min(dw, dh));
    final w = _even(dw * scale), h = _even(dh * scale);
    // Already small enough and no resizing needed: re-encoding would only hurt.
    final srcBytes = info.fileSize;
    if (!trimming && srcBytes != null && totalMs > 0 && min(dw, dh) <= shortSide) {
      final sec = max(1, (totalMs / 1000).ceil());
      if (srcBytes <= estimateMb(preset.mbps, sec) * 1000000) {
        final mb = srcBytes / 1000000;
        return [
          PartResult(File(path), info.displayWidth, info.displayHeight, mb,
              mb * 8 / sec,
              untouched: true)
        ];
      }
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = <PartResult>[];

    for (var i = 0; i < parts; i++) {
      onPart?.call(i + 1, parts);
      final startMs = i * segmentSeconds * 1000;
      final endMs = trimming ? min(totalMs, startMs + segmentSeconds * 1000) : totalMs;
      final segSec = max(1, ((trimming ? endMs - startMs : totalMs) / 1000).ceil());
      final mb = estimateMb(preset.mbps, segSec);
      final edit = trimming ? VideoEdit(trimStartMs: startMs, trimEndMs: endMs) : null;
      final name = 'status_${stamp}_p${i + 1}.mp4';

      var r = await _encode(path, w, h, mb, edit, name);
      if (r is OnSuccess) {
        var o = await _c.getMediaInfo(r.destinationPath);
        // If the plugin read width/height as pre-rotation values, the output
        // orientation flips. Detect that and retry once with swapped sizes.
        final flipped = ((o.displayWidth ?? 0) > (o.displayHeight ?? 0)) != (dw > dh);
        if (flipped) {
          r = await _encode(path, h, w, mb, edit, 'swap_$name');
          if (r is OnSuccess) o = await _c.getMediaInfo(r.destinationPath);
        }
        if (r is OnSuccess) {
          final sizeMb = r.compressedSize / 1000000;
          out.add(PartResult(File(r.destinationPath), o.displayWidth,
              o.displayHeight, sizeMb, sizeMb * 8 / segSec));
          continue;
        }
      }
      if (r is OnCancelled) break;
      if (r is OnFailure) throw Exception(r.message);
    }
    return out;
  }

  Future<void> cancel() => _c.cancelCompression();
  Future<void> clearCache() => _c.clearCache();
}
