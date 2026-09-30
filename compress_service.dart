import 'dart:io';
import 'package:video_compress/video_compress.dart';

enum StatusPreset {
  hd720('720p (smaller, safest)', VideoQuality.Res1280x720Quality),
  fullHd1080('1080p (sharpest)', VideoQuality.Res1920x1080Quality);

  const StatusPreset(this.label, this.quality);
  final String label;
  final VideoQuality quality;
}

class CompressService {
  static const segmentSeconds = 30;

  /// Returns the list of compressed files (one per 30s segment if [split]).
  /// Note: do NOT edit/crop the outputs afterwards; that re-encodes them.
  Future<List<File>> run(
    String inputPath, {
    required StatusPreset preset,
    required bool split,
    void Function(int done, int total)? onSegment,
  }) async {
    final info = await VideoCompress.getMediaInfo(inputPath);
    final totalSec = ((info.duration ?? 0) / 1000).ceil();
    final segments = (split && totalSec > segmentSeconds)
        ? (totalSec / segmentSeconds).ceil()
        : 1;

    final out = <File>[];
    for (var i = 0; i < segments; i++) {
      onSegment?.call(i + 1, segments);
      final result = await VideoCompress.compressVideo(
        inputPath,
        quality: preset.quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
        startTime: segments > 1 ? i * segmentSeconds : null,
        duration: segments > 1 ? segmentSeconds : null,
      );
      if (result?.file != null) out.add(result!.file!);
    }
    return out;
  }

  Future<void> cancel() => VideoCompress.cancelCompression();
  Future<void> clearCache() => VideoCompress.deleteAllCache();
}
