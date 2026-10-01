import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class PitchResult {
  final double? frequencyHz;
  final double confidence;
  final String? note;
  final int? octave;
  final double? cents;

  PitchResult({
    required this.frequencyHz,
    required this.confidence,
    required this.note,
    required this.octave,
    required this.cents,
  });

  factory PitchResult.fromJson(Map<String, dynamic> json) {
    return PitchResult(
      frequencyHz: (json['frequencyHz'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String?,
      octave: json['octave'] as int?,
      cents: (json['cents'] as num?)?.toDouble(),
    );
  }
}

/// A message already safe to show a user — never a raw stack trace, HTML
/// error page, or "Exception: ..." dump. `toString()` returns the message
/// directly, so existing `'$e'` interpolations show it as-is.
class SrugatiApiException implements Exception {
  final String message;
  const SrugatiApiException(this.message);
  @override
  String toString() => message;
}

const maxUploadBytes = 100 * 1024 * 1024;

String _friendlyServerError(int statusCode, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['detail'] is String) {
      return decoded['detail'] as String;
    }
  } catch (_) {
    // Not JSON (e.g. an infra error page) — fall through to a generic message.
  }
  if (statusCode == 413) return "This file is too large — please choose one under 100MB.";
  if (statusCode >= 500) return "Something went wrong on the server. Please try again.";
  if (statusCode == 400) return "Could not process this file — please try a different one.";
  return "Something went wrong. Please try again.";
}

/// Thin client for the SruGati Engine — pitch detection and independent
/// pitch/tempo shifting for any audio or video file.
class SrugatiApi {
  static const String baseUrl = String.fromEnvironment(
    'SRUGATI_API_BASE_URL',
    defaultValue: 'https://srugati-engine-236220033725.us-central1.run.app',
  );

  static Future<PitchResult> detectPitch(String filePath) async {
    try {
      final size = await File(filePath).length();
      if (size > maxUploadBytes) {
        throw const SrugatiApiException("This file is too large — please choose one under 100MB.");
      }

      final uri = Uri.parse('$baseUrl/pitch/detect');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamed = await request.send().timeout(const Duration(minutes: 3));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw SrugatiApiException(_friendlyServerError(streamed.statusCode, body));
      }
      return PitchResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } on SrugatiApiException {
      rethrow;
    } on TimeoutException {
      throw const SrugatiApiException("The server took too long to respond. Please try again.");
    } on SocketException {
      throw const SrugatiApiException("Couldn't reach the server — check your connection and try again.");
    } catch (_) {
      throw const SrugatiApiException("Something went wrong. Please try again.");
    }
  }

  /// Shifts [filePath] by [semitones] and/or [tempo] (1.0 == unchanged) and
  /// saves the result to [outputPath]. Returns the saved path.
  ///
  /// Pass [client] to make the request cancellable: closing that client
  /// (e.g. from a "Cancel" button) aborts the in-flight request instead of
  /// waiting for [timeout]. If omitted, a client is created and closed
  /// internally as usual. A deliberate cancel surfaces as [http.ClientException]
  /// unchanged (not wrapped in [SrugatiApiException]) so callers can still
  /// tell a cancel apart from a real failure.
  /// [want]: "auto" (video in -> video out, audio in -> audio out — the
  /// normal Studio flow), "audio" (always return just the shifted audio,
  /// even for a video upload), or "video" (video upload only).
  /// [outputFormat]: "auto", or for want="audio" one of "m4a"/"mp3"/"wav";
  /// for a video result one of "mp4"/"mov".
  static Future<String> shift({
    required String filePath,
    required double semitones,
    required double tempo,
    required String label,
    required String outputPath,
    bool preserveFormant = true,
    String want = 'auto',
    String outputFormat = 'auto',
    http.Client? client,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final ownsClient = client == null;
    final c = client ?? http.Client();
    try {
      final size = await File(filePath).length();
      if (size > maxUploadBytes) {
        throw const SrugatiApiException("This file is too large — please choose one under 100MB.");
      }

      final uri = Uri.parse('$baseUrl/pitch/shift');
      final request = http.MultipartRequest('POST', uri)
        ..fields['semitones'] = semitones.toString()
        ..fields['tempo'] = tempo.toString()
        ..fields['label'] = label
        ..fields['preserve_formant'] = preserveFormant.toString()
        ..fields['want'] = want
        ..fields['output_format'] = outputFormat
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamed = await c.send(request).timeout(timeout);
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        throw SrugatiApiException(_friendlyServerError(streamed.statusCode, body));
      }

      final bytes = await streamed.stream.toBytes();
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(bytes, flush: true);
      return outFile.path;
    } on SrugatiApiException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } on TimeoutException {
      throw const SrugatiApiException("The server took too long to respond. Please try again.");
    } on SocketException {
      throw const SrugatiApiException("Couldn't reach the server — check your connection and try again.");
    } catch (_) {
      throw const SrugatiApiException("Something went wrong. Please try again.");
    } finally {
      if (ownsClient) c.close();
    }
  }
}
