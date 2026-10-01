# SruGati

Indian-classical-friendly pitch/tempo shifting for any song, audio or video.

- `srugati_app/` — Flutter client (iOS/Android): upload, pitch detection, live local
  pitch/tempo preview, server-rendered formant-preserved shifts, Library, download.
- `srugati_engine/` — FastAPI backend (deployed on Cloud Run): pitch detection (aubio)
  and independent pitch/tempo shifting via ffmpeg's Rubber Band filter.
