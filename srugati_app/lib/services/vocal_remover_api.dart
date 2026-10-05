import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'srugati_api.dart' show SrugatiApiException;

/// Where a stem-separation job is, as reported by the vocal remover service.
class StemJob {
  final String id;
  final String status;
  final int progress;
  final String? stage;
  final String? error;
  final Map<String, String> stems;

  const StemJob({
    required this.id,
    required this.status,
    this.progress = 0,
    this.stage,
    this.error,
    this.stems = const {},
  });

  factory StemJob.fromJson(Map<String, dynamic> j) => StemJob(
    id: j['job_id'] as String,
    status: j['status'] as String,
    progress: (j['progress'] as num?)?.round() ?? 0,
    stage: j['stage'] as String?,
    error: j['error'] as String?,
    stems: ((j['stems'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, v as String),
    ),
  );
}

/// Client for the Demucs vocal-remover service (separate from the SruGati
/// pitch engine). Songs go straight to Cloud Storage through a signed URL,
/// because Cloud Run caps request bodies well under real song sizes.
class VocalRemoverApi {
  static const String baseUrl = String.fromEnvironment(
    'VOCAL_REMOVER_API_URL',
    defaultValue: 'https://vocal-remover-api-971205881162.us-central1.run.app',
  );

  static const maxUploadBytes = 500 * 1024 * 1024;

  /// The service only accepts a fixed set of declared content types; anything
  /// else we can decode is declared as a close relative (the file's real
  /// format is detected from its bytes by ffmpeg on the worker).
  static String contentTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.wav':
        return 'audio/wav';
      case '.flac':
        return 'audio/flac';
      case '.m4a':
        return 'audio/mp4';
      case '.mp4':
      case '.mov':
      case '.m4v':
      case '.mkv':
      case '.webm':
      case '.avi':
        return 'video/mp4';
      default:
        return 'audio/mpeg';
    }
  }

  static String _friendly(
    http.BaseResponse response,
    String body,
    String fallback,
  ) {
    try {
      final detail = jsonDecode(body);
      if (detail is Map && detail['detail'] is String)
        return detail['detail'] as String;
    } catch (_) {}
    if (response.statusCode >= 500)
      return 'The vocal remover had a problem. Please try again.';
    return fallback;
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on SrugatiApiException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } on TimeoutException {
      throw const SrugatiApiException(
        'The vocal remover took too long to respond. Please try again.',
      );
    } on SocketException {
      throw const SrugatiApiException(
        "Couldn't reach the vocal remover — check your connection and try again.",
      );
    } catch (_) {
      throw const SrugatiApiException(
        'Something went wrong. Please try again.',
      );
    }
  }

  /// Registers a job and returns where to upload the file.
  static Future<({String jobId, String uploadUrl, String contentType})>
  createJob(
    String filename,
    String contentType, {
    required http.Client client,
  }) {
    return _guard(() async {
      final response = await client
          .post(
            Uri.parse('$baseUrl/jobs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'filename': filename,
              'content_type': contentType,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SrugatiApiException(
          _friendly(response, response.body, 'Could not start the job.'),
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        jobId: json['job_id'] as String,
        uploadUrl: json['upload_url'] as String,
        contentType: json['content_type'] as String,
      );
    });
  }

  /// Streams [path] to the signed [uploadUrl], reporting 0..1 progress.
  static Future<void> upload(
    String uploadUrl,
    String path,
    String contentType, {
    required http.Client client,
    required void Function(double) onProgress,
  }) {
    return _guard(() async {
      final file = File(path);
      final size = await file.length();
      if (size > maxUploadBytes) {
        throw const SrugatiApiException(
          'This file is too large — the limit is 500MB.',
        );
      }

      final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl))
        ..headers['Content-Type'] = contentType
        ..contentLength = size;

      var sent = 0;
      unawaited(
        request.sink
            .addStream(
              file.openRead().map((chunk) {
                sent += chunk.length;
                onProgress(sent / size);
                return chunk;
              }),
            )
            .then((_) => request.sink.close()),
      );

      final response = await client.send(request);
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SrugatiApiException(
          'The upload failed (${response.statusCode}). Please try again.',
        );
      }
    });
  }

  static Future<void> confirm(String jobId, {required http.Client client}) {
    return _guard(() async {
      final response = await client
          .post(Uri.parse('$baseUrl/jobs/$jobId/confirm'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SrugatiApiException(
          _friendly(response, response.body, 'Could not queue the job.'),
        );
      }
    });
  }

  static Future<StemJob> getJob(String jobId, {required http.Client client}) {
    return _guard(() async {
      final response = await client
          .get(Uri.parse('$baseUrl/jobs/$jobId'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SrugatiApiException(
          _friendly(response, response.body, 'Could not check the job.'),
        );
      }
      return StemJob.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    });
  }

  /// Asks the service to stop the job (it kills the separation if running).
  /// Best-effort: the caller has already stopped waiting either way.
  static Future<void> cancel(String jobId) async {
    try {
      await http
          .post(Uri.parse('$baseUrl/jobs/$jobId/cancel'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  static Future<void> download(
    String url,
    String destPath, {
    required http.Client client,
    required void Function(double) onProgress,
  }) {
    return _guard(() async {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw SrugatiApiException(
          'Downloading the result failed (${response.statusCode}).',
        );
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = File(destPath).openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
    });
  }
}
