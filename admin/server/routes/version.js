const express = require('express');
const router = express.Router();
const fs = require('fs');
const path = require('path');

// 当前最新版本信息（可以从文件或数据库读取）
let latestVersion = {
  versionCode: 2,
  versionName: '0.1.1',
  buildTime: Date.now(),
  downloadUrl: 'https://www.beelzebub.top/downloads/cctt-v0.1.1.apk',
  fileSize: 0, // 字节
  md5: '',
  changelog: [
    '新增：按日期生成出货和进货汇总',
    '新增：进货客户及品类统计',
    '新增：云端版本检查和应用内安装',
    '修复：设置页检查更新返回 401'
  ],
  forceUpdate: false, // 是否强制更新
  minVersion: 1 // 最低支持的版本号，低于此版本必须更新
};

/**
 * GET /api/version/check
 * 检查更新
 *
 * 请求参数：
 * - currentVersion: 当前APP版本号（versionCode）
 *
 * 返回：
 * - hasUpdate: 是否有更新
 * - forceUpdate: 是否强制更新
 * - latest: 最新版本信息
 */
router.get('/check', (req, res) => {
  const currentVersion = parseInt(req.query.currentVersion || '0');

  const hasUpdate = currentVersion < latestVersion.versionCode;
  const forceUpdate = currentVersion < latestVersion.minVersion;

  res.json({
    success: true,
    hasUpdate,
    forceUpdate,
    latest: hasUpdate ? latestVersion : null,
    message: hasUpdate
      ? (forceUpdate ? '发现新版本，请立即更新' : '发现新版本，建议更新')
      : '已是最新版本'
  });
});

/**
 * GET /api/version/latest
 * 获取最新版本信息
 */
router.get('/latest', (req, res) => {
  res.json({
    success: true,
    data: latestVersion
  });
});

/**
 * POST /api/version/update
 * 更新版本信息（管理员接口）
 *
 * 请求体：
 * - versionCode: 版本号
 * - versionName: 版本名称
 * - downloadUrl: 下载地址
 * - changelog: 更新日志
 * - forceUpdate: 是否强制更新
 */
router.post('/update', (req, res) => {
  const remoteAddress = req.socket.remoteAddress || '';
  const forwardedFor = req.headers['x-forwarded-for'];
  const isLoopback = remoteAddress === '127.0.0.1' ||
    remoteAddress === '::1' ||
    remoteAddress === '::ffff:127.0.0.1';
  if (forwardedFor || !isLoopback) {
    return res.status(403).json({
      success: false,
      message: '仅允许服务器本机更新版本信息'
    });
  }

  const { versionCode, versionName, downloadUrl, changelog, forceUpdate, minVersion, fileSize, md5 } = req.body;

  if (!versionCode || !versionName || !downloadUrl) {
    return res.status(400).json({
      success: false,
      message: '缺少必要参数'
    });
  }

  latestVersion = {
    versionCode: parseInt(versionCode),
    versionName,
    buildTime: Date.now(),
    downloadUrl,
    fileSize: fileSize || 0,
    md5: md5 || '',
    changelog: changelog || [],
    forceUpdate: forceUpdate || false,
    minVersion: minVersion || 1
  };

  // 持久化到文件（可选）
  const versionFile = path.join(__dirname, '../data/version.json');
  try {
    fs.mkdirSync(path.dirname(versionFile), { recursive: true });
    fs.writeFileSync(versionFile, JSON.stringify(latestVersion, null, 2));
  } catch (err) {
    console.error('保存版本信息失败:', err);
  }

  res.json({
    success: true,
    message: '版本信息已更新',
    data: latestVersion
  });
});

/**
 * 启动时加载版本信息
 */
function loadVersionInfo() {
  const versionFile = path.join(__dirname, '../data/version.json');
  if (fs.existsSync(versionFile)) {
    try {
      const data = fs.readFileSync(versionFile, 'utf8');
      latestVersion = JSON.parse(data);
      console.log('[Version] 已加载版本信息:', latestVersion.versionName);
    } catch (err) {
      console.error('[Version] 加载版本信息失败:', err);
    }
  }
}

// 初始化
loadVersionInfo();

module.exports = router;
