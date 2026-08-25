const express = require('express');
const fs = require('fs');
const path = require('path');

const router = express.Router();
const releasesDir = path.resolve(__dirname, '..', '..', 'releases');
const manifestPath = path.join(releasesDir, 'latest.json');

function loadManifest() {
  if (!fs.existsSync(manifestPath)) {
    const error = new Error('版本清单不存在');
    error.statusCode = 503;
    throw error;
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (!manifest.versionName || !Number.isInteger(manifest.versionCode)) {
    const error = new Error('版本清单格式无效');
    error.statusCode = 500;
    throw error;
  }
  return manifest;
}

function publicBaseUrl(req) {
  const configured = (process.env.PUBLIC_BASE_URL || '').replace(/\/$/, '');
  return configured || `${req.protocol}://${req.get('host')}`;
}

// GET /api/app-update/latest — 查询最新 Android 版本。
router.get('/latest', (req, res) => {
  try {
    const manifest = loadManifest();
    const apkFile = path.basename(manifest.apkFile || '');
    const apkPath = apkFile ? path.join(releasesDir, apkFile) : null;
    const localApkExists = Boolean(apkPath && fs.existsSync(apkPath));
    const apkUrl = manifest.apkUrl ||
      (localApkExists
        ? `${publicBaseUrl(req)}/api/app-update/download/${encodeURIComponent(apkFile)}`
        : null);

    res.json({
      versionName: manifest.versionName,
      versionCode: manifest.versionCode,
      mandatory: Boolean(manifest.mandatory),
      apkUrl,
      sha256: manifest.sha256 || '',
      releaseNotes: manifest.releaseNotes || '',
      publishedAt: manifest.publishedAt || null,
      available: Boolean(apkUrl),
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({ error: error.message });
  }
});

// GET /api/app-update/download/:file — 下载清单指定的 APK。
router.get('/download/:file', (req, res) => {
  try {
    const manifest = loadManifest();
    const requestedFile = path.basename(req.params.file);
    const allowedFile = path.basename(manifest.apkFile || '');
    if (!requestedFile || requestedFile !== allowedFile) {
      return res.status(404).json({ error: '安装包不存在' });
    }

    const apkPath = path.join(releasesDir, requestedFile);
    if (!fs.existsSync(apkPath)) {
      return res.status(404).json({ error: '安装包尚未上传' });
    }
    return res.download(apkPath, requestedFile);
  } catch (error) {
    return res.status(error.statusCode || 500).json({ error: error.message });
  }
});

module.exports = router;

