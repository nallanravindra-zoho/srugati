import { useEffect, useRef, useState } from "react";
import "./App.css";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8080";
const POLL_INTERVAL_MS = 3000;

function putWithProgress(url, file, contentType, onProgress, signal) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", url);
    xhr.setRequestHeader("Content-Type", contentType);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100));
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else reject(new Error(`Upload to storage failed (${xhr.status})`));
    };
    xhr.onerror = () => reject(new Error("Upload to storage failed"));
    xhr.onabort = () => reject(new DOMException("Aborted", "AbortError"));
    signal?.addEventListener("abort", () => xhr.abort());
    xhr.send(file);
  });
}

function App() {
  const [file, setFile] = useState(null);
  const [job, setJob] = useState(null); // { job_id, status, stems, error }
  const [uploading, setUploading] = useState(false);
  const [uploadPercent, setUploadPercent] = useState(0);
  const [uploadError, setUploadError] = useState(null);
  const pollRef = useRef(null);
  const abortRef = useRef(null);

  const stopTracking = () => {
    clearInterval(pollRef.current);
    pollRef.current = null;
    abortRef.current?.abort();
    abortRef.current = null;
  };

  useEffect(() => stopTracking, []);

  const pollJob = (jobId) => {
    pollRef.current = setInterval(async () => {
      try {
        const res = await fetch(`${API_URL}/jobs/${jobId}`);
        if (!res.ok) throw new Error(`Status check failed (${res.status})`);
        const data = await res.json();
        setJob(data);
        if (data.status === "done" || data.status === "failed") {
          clearInterval(pollRef.current);
          pollRef.current = null;
        }
      } catch (err) {
        clearInterval(pollRef.current);
        pollRef.current = null;
        setUploadError(err.message);
      }
    }, POLL_INTERVAL_MS);
  };

  const handleUpload = async () => {
    if (!file) return;
    // Starting a new job abandons tracking of whatever was running before —
    // that job keeps processing server-side, we just stop watching it.
    stopTracking();
    setUploading(true);
    setUploadPercent(0);
    setUploadError(null);
    setJob(null);

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      // 1. Ask the API for a place to put the file. Cloud Run caps request
      // bodies at 32MB, too small for real songs, so the browser uploads
      // straight to Cloud Storage via a signed URL instead of routing the
      // file through the API.
      const createRes = await fetch(`${API_URL}/jobs`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filename: file.name, content_type: file.type }),
        signal: controller.signal,
      });
      if (!createRes.ok) {
        const body = await createRes.json().catch(() => ({}));
        throw new Error(body.detail || `Could not start upload (${createRes.status})`);
      }
      const { job_id, upload_url, content_type } = await createRes.json();
      setJob({ job_id, status: "uploading" });

      // 2. Upload the file bytes directly to storage.
      await putWithProgress(upload_url, file, content_type, setUploadPercent, controller.signal);

      // 3. Tell the API the upload is done so it can queue the job.
      const confirmRes = await fetch(`${API_URL}/jobs/${job_id}/confirm`, {
        method: "POST",
        signal: controller.signal,
      });
      if (!confirmRes.ok) {
        const body = await confirmRes.json().catch(() => ({}));
        throw new Error(body.detail || `Could not queue job (${confirmRes.status})`);
      }
      const data = await confirmRes.json();
      setJob(data);
      pollJob(job_id);
    } catch (err) {
      if (err.name !== "AbortError") setUploadError(err.message);
    } finally {
      setUploading(false);
    }
  };

  const handleCancel = () => {
    stopTracking();
    setUploading(false);
    setJob(null);
    setUploadError(null);
  };

  const isTracking = uploading || job?.status === "queued" || job?.status === "processing";

  return (
    <div className="page">
      <h1>Vocal Remover</h1>
      <p className="subtitle">Separate any song into vocals and instrumental tracks.</p>

      <div className="upload-box">
        <input
          type="file"
          accept="audio/*,video/mp4,.mp3,.wav,.flac,.mp4,.m4a"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />
        <button onClick={handleUpload} disabled={!file || uploading}>
          {uploading ? `Uploading... ${uploadPercent}%` : "Separate"}
        </button>
        {isTracking && (
          <button className="cancel" onClick={handleCancel}>
            Cancel
          </button>
        )}
      </div>

      {uploadError && <p className="error">{uploadError}</p>}

      {job && (
        <div className="job-status">
          <p>
            Job <code>{job.job_id}</code> — status: <strong>{job.status}</strong>
          </p>

          {job.status === "queued" || job.status === "processing" ? (
            <p className="hint">
              This can take a few minutes (CPU-only processing). You can pick a different
              file and hit Separate, or Cancel, at any time — it won't stop this job on the
              server, it just stops watching it here.
            </p>
          ) : null}

          {job.status === "failed" && <p className="error">{job.error}</p>}

          {job.status === "done" && job.stems && (
            <div className="stems">
              {Object.entries(job.stems).map(([name, url]) => (
                <div className="stem" key={name}>
                  <h3>{name}</h3>
                  <audio controls src={url} />
                  <a href={url} download={`${name}.wav`}>
                    Download
                  </a>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default App;
