import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

class WavInfo {
  final List<double> peaks;
  final double durationSec;
  const WavInfo(this.peaks, this.durationSec);
}

/// Reads a PCM/float WAV and returns [bars] loudness peaks (0..1) plus its
/// duration — a real picture of the stem, computed off the UI thread.
Future<WavInfo> computeWavPeaks(String path, {int bars = 140}) =>
    Isolate.run(() => _compute(path, bars));

WavInfo _compute(String path, int bars) {
  final raf = File(path).openSync();
  try {
    final length = raf.lengthSync();
    var format = 1, channels = 2, sampleRate = 44100, bits = 16;
    var dataStart = -1, dataSize = 0;

    var offset = 12;
    while (offset + 8 <= length) {
      raf.setPositionSync(offset);
      final header = ByteData.sublistView(raf.readSync(8));
      final id = String.fromCharCodes(header.buffer.asUint8List(0, 4));
      var size = header.getUint32(4, Endian.little);
      if (id == 'fmt ') {
        raf.setPositionSync(offset + 8);
        final fmt = ByteData.sublistView(raf.readSync(16));
        format = fmt.getUint16(0, Endian.little);
        channels = fmt.getUint16(2, Endian.little);
        sampleRate = fmt.getUint32(4, Endian.little);
        bits = fmt.getUint16(14, Endian.little);
      } else if (id == 'data') {
        dataStart = offset + 8;
        dataSize = min(size, length - dataStart);
        break;
      }
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    if (dataStart < 0) throw const FormatException('Not a WAV file');

    final bytesPerSample = bits ~/ 8;
    final frameBytes = bytesPerSample * channels;
    final frames = dataSize ~/ frameBytes;
    final peaks = List<double>.filled(bars, 0);

    const block = 1 << 20;
    raf.setPositionSync(dataStart);
    var framesRead = 0;
    var remaining = frames * frameBytes;
    while (remaining > 0) {
      final take = min(block - block % frameBytes, remaining);
      final bytes = raf.readSync(take);
      if (bytes.isEmpty) break;
      final view = ByteData.sublistView(Uint8List.fromList(bytes));
      final framesInBlock = bytes.length ~/ frameBytes;
      for (var f = 0; f < framesInBlock; f++) {
        final bar = min(bars - 1, ((framesRead + f) * bars) ~/ frames);
        for (var c = 0; c < channels; c++) {
          final at = f * frameBytes + c * bytesPerSample;
          final double v;
          if (format == 3 && bits == 32) {
            v = view.getFloat32(at, Endian.little).abs();
          } else if (bits == 16) {
            v = view.getInt16(at, Endian.little).abs() / 32768;
          } else if (bits == 24) {
            var s =
                view.getUint8(at) |
                (view.getUint8(at + 1) << 8) |
                (view.getUint8(at + 2) << 16);
            if (s & 0x800000 != 0) s -= 0x1000000;
            v = s.abs() / 8388608;
          } else {
            v = view.getInt32(at, Endian.little).abs() / 2147483648;
          }
          if (v > peaks[bar]) peaks[bar] = v;
        }
      }
      framesRead += framesInBlock;
      remaining -= bytes.length;
    }

    final top = peaks.reduce(max);
    final normalised = top <= 0
        ? peaks
        : peaks.map((v) => sqrt(v / top)).toList();
    return WavInfo(normalised, frames / sampleRate);
  } finally {
    raf.closeSync();
  }
}
