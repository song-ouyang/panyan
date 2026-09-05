// wx.compressVideo returns kB; only getFileInfo supplies authoritative byte sizes.
// API contract: https://github.com/wechat-miniprogram/api-typings
const STORAGE_PREFIX = 'wanpan:video-upload:v1:';
const CACHE_TTL = 7 * 24 * 60 * 60 * 1000;
const PROFILE = '1080p-30fps-2500kbps-v1';
const MAX_WORKERS = 3;
const MAX_ATTEMPTS = 4;

function createVideoUploader({ wx: platform, request, uploadLocal, apiBaseUrl, uploadMode,
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)), now = Date.now, random = Math.random }) {
  const active = new Map();
  const fs = platform.getFileSystemManager();
  const call = (owner, method, options) => new Promise((resolve, reject) => {
    owner[method]({ ...options, success: resolve, fail: reject });
  });
  const fileInfo = path => call(platform, 'getFileInfo', { filePath: path, digestAlgorithm: 'sha1' });
  const isMissing = error => error.statusCode === 404 && error.code === 'UPLOAD_NOT_FOUND';
  const retryable = error => !error.statusCode || error.statusCode === 408 || error.statusCode === 429 || error.statusCode >= 500 || error.retryable === true;

  function readRecord(key) {
    const record = platform.getStorageSync(key);
    return record && typeof record === 'object' ? record : null;
  }

  function saveRecord(key, record) {
    try { platform.setStorageSync(key, { ...record, updatedAt: now() }); }
    catch (_) { throw new Error('无法保存上传进度，请清理微信存储空间后重试'); }
  }

  async function removeFile(filePath) {
    if (!filePath) return;
    try { await call(fs, 'unlink', { filePath }); } catch (_) { /* Already removed by WeChat. */ }
  }

  async function pruneCache() {
    const { keys } = platform.getStorageInfoSync();
    for (const key of keys.filter(value => value.startsWith(STORAGE_PREFIX))) {
      const record = readRecord(key);
      if (!record || now() - record.updatedAt <= CACHE_TTL || active.has(key)) continue;
      await removeFile(record.filePath);
      platform.removeStorageSync(key);
    }
  }

  async function retry(operation) {
    for (let attempt = 0; ; attempt += 1) {
      try { return await operation(); }
      catch (error) {
        if (!retryable(error) || attempt >= MAX_ATTEMPTS - 1) throw error;
        await sleep(Math.max(error.retryAfterMs || 0, 500 * (2 ** attempt) + Math.floor(random() * 250)));
      }
    }
  }

  async function prepare(filePath, source, cacheKey, record, onStage) {
    if (record && record.filePath) {
      try {
        const actual = await fileInfo(record.filePath);
        if (actual.size === record.size && actual.digest === record.digest) return record;
      } catch (_) { /* A removed/corrupted local artifact must be prepared again. */ }
      await removeFile(record.filePath);
    }
    onStage('compressing');
    if (!platform.compressVideo || !platform.getVideoInfo) {
      throw new Error('当前微信版本不支持视频压缩，请更新微信后重试');
    }
    let compressed;
    let savedPath;
    let saved = false;
    try {
      const info = await call(platform, 'getVideoInfo', { src: filePath });
      const longest = Math.max(info.width, info.height);
      const shortest = Math.min(info.width, info.height);
      if (!(shortest > 0)) throw new Error('视频尺寸无效');
      compressed = await call(platform, 'compressVideo', {
        src: filePath,
        bitrate: Math.min(2500, info.bitrate > 0 ? info.bitrate : 2500),
        fps: Math.min(30, info.fps > 0 ? info.fps : 30),
        resolution: Math.min(1, 1920 / longest, 1080 / shortest)
      });
      if (!compressed.tempFilePath || compressed.tempFilePath === filePath) throw new Error('没有生成压缩视频');
      const compressedInfo = await fileInfo(compressed.tempFilePath);
      if (!(compressedInfo.size > 0) || !compressedInfo.digest) throw new Error('压缩视频无效');
      const outputInfo = await call(platform, 'getVideoInfo', { src: compressed.tempFilePath });
      if (!/^(video\/)?mp4$/i.test(outputInfo.type || '')) throw new Error('压缩视频格式不是 MP4');
      if (!(info.duration > 0) || !(outputInfo.duration > 0) || Math.abs(info.duration - outputInfo.duration) > Math.max(0.5, info.duration * 0.01)) {
        throw new Error('压缩视频时长不完整');
      }
      // Successful recompression can grow an already efficient clip; keep the smaller bytes.
      const useCompressed = compressedInfo.size < source.size;
      const selectedPath = useCompressed ? compressed.tempFilePath : filePath;
      const selectedInfo = useCompressed ? compressedInfo : source;
      // copyFile preserves the selected original (saveFile moves temporary files).
      savedPath = `${platform.env.USER_DATA_PATH}/wanpan-video-${now()}-${random().toString(16).slice(2)}.mp4`;
      await call(fs, 'copyFile', { srcPath: selectedPath, destPath: savedPath });
      const actual = await fileInfo(savedPath);
      if (actual.size !== selectedInfo.size || actual.digest !== selectedInfo.digest) {
        await removeFile(savedPath);
        throw new Error('保存的视频不完整');
      }
      // Only carry an OSS upload across regeneration if the output bytes are identical.
      const sameOutput = record && record.size === actual.size && record.digest === actual.digest;
      const prepared = {
        filePath: savedPath, size: actual.size, digest: actual.digest,
        originalSize: source.size, task: sameOutput ? record.task : null,
        parts: sameOutput ? record.parts : []
      };
      saveRecord(cacheKey, prepared);
      saved = true;
      return prepared;
    } catch (error) {
      if (error.message && /微信存储空间/.test(error.message)) throw error;
      throw new Error('视频压缩或保存失败，请清理存储空间后重试');
    } finally {
      if (compressed && compressed.tempFilePath !== filePath) await removeFile(compressed.tempFilePath);
      if (savedPath && !saved) await removeFile(savedPath);
    }
  }

  async function putPart(url, data) {
    const response = await call(platform, 'request', {
      url, method: 'PUT', data, timeout: 60000,
      header: { 'content-type': 'application/octet-stream' }
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      const error = new Error(`分片上传失败（${response.statusCode}）`);
      error.statusCode = response.statusCode;
      // Refresh the signed URL on every attempt, including OSS expiry responses.
      error.retryable = response.statusCode === 403;
      throw error;
    }
    const entry = Object.entries(response.header || {}).find(([key]) => key.toLowerCase() === 'etag');
    if (!entry || !entry[1]) throw new Error('OSS 未返回 ETag，请检查上传配置');
    return entry[1];
  }

  async function run(filePath, source, cacheKey, userId, onProgress, onStage) {
    const uploadRequest = (path, options) => request(path, { ...options, expectedUserId: userId });
    let record = readRecord(cacheKey);
    record = await prepare(filePath, source, cacheKey, record, onStage);
    onStage('uploading', { originalSize: source.size, size: record.size });
    onProgress(0);
    if (uploadMode !== 'oss') {
      const result = await uploadLocal(record.filePath, value => onProgress(Math.min(99, value)), userId);
      const savedPath = record.filePath;
      platform.removeStorageSync(cacheKey);
      await removeFile(savedPath);
      onProgress(100);
      return { ...result, ownerId: userId };
    }

    const status = () => retry(() => uploadRequest('/uploads/multipart/status', {
      method: 'POST', data: { key: record.task.key, uploadId: record.task.uploadId }
    }));
    const finished = async result => {
      if (!result.url || (result.size != null && result.size !== record.size)) throw new Error('上传结果与视频大小不一致，请重试');
      // Keep the source artifact/task until cache expiry. A later reuse must confirm OSS
      // still owns the completed object (a deleted post may already have removed it).
      saveRecord(cacheKey, { ...record, completed: result });
      onProgress(100);
      return { ...result, ownerId: userId };
    };
    try {
      if (record.task) {
        try {
          const existing = await status();
          if (existing.state === 'completed') return await finished(existing);
          if (existing.state !== 'uploading' || !Array.isArray(existing.parts)) throw new Error('无法确认视频上传进度，请稍后重试');
          // OSS is authoritative: recover acknowledgements lost before the local checkpoint.
          record.parts = existing.parts;
        } catch (error) {
          if (!isMissing(error)) throw error;
          record.task = null;
          record.parts = [];
          saveRecord(cacheKey, record);
        }
      }
      if (!record.task) {
        record.task = await uploadRequest('/uploads/multipart/init', {
          method: 'POST', data: { filename: 'send.mp4', mimeType: 'video/mp4', size: record.size }
        });
        record.parts = [];
        saveRecord(cacheKey, record);
      }
      const { key, uploadId, partSize } = record.task;
      if (!key || !uploadId || !Number.isInteger(partSize) || partSize <= 0) throw new Error('上传配置无效，请稍后重试');
      const total = Math.ceil(record.size / partSize);
      const lengthFor = number => Math.min(partSize, record.size - (number - 1) * partSize);
      const confirmed = new Map();
      for (const part of record.parts || []) {
        if (Number.isInteger(part.number) && part.number >= 1 && part.number <= total && part.etag && part.size === lengthFor(part.number)) {
          confirmed.set(part.number, part);
        }
      }
      record.parts = Array.from(confirmed.values());
      saveRecord(cacheKey, record);
      let completedBytes = record.parts.reduce((sum, part) => sum + part.size, 0);
      const progress = () => onProgress(Math.min(99, Math.floor(completedBytes / record.size * 100)));
      progress();
      const pending = Array.from({ length: total }, (_, index) => index + 1).filter(number => !confirmed.has(number));
      let next = 0;
      let failure;
      const worker = async () => {
        while (!failure && next < pending.length) {
          const number = pending[next++];
          try {
            const length = lengthFor(number);
            const chunk = await call(fs, 'readFile', { filePath: record.filePath, position: (number - 1) * partSize, length });
            if (!chunk.data || chunk.data.byteLength !== length) throw new Error('本地视频读取不完整，请重新选择视频');
            const etag = await retry(async () => {
              const signed = await uploadRequest('/uploads/multipart/part-url', { method: 'POST', data: { key, uploadId, partNumber: number } });
              return putPart(signed.url, chunk.data);
            });
            record.parts.push({ number, etag, size: length });
            saveRecord(cacheKey, record);
            completedBytes += length;
            progress();
          } catch (error) { failure = failure || error; }
        }
      };
      // Settle every in-flight worker before returning, so a subsequent retry cannot race it.
      await Promise.all(Array.from({ length: Math.min(MAX_WORKERS, pending.length) }, worker));
      if (failure) throw failure;
      onStage('finishing');
      const parts = record.parts.slice().sort((a, b) => a.number - b.number).map(({ number, etag }) => ({ number, etag }));
      const result = await retry(async () => {
        try { return await uploadRequest('/uploads/multipart/complete', { method: 'POST', data: { key, uploadId, parts } }); }
        catch (error) {
          // Complete may succeed while its response is lost. Recover the object before retrying.
          if (retryable(error) || isMissing(error)) {
            const existing = await status();
            if (existing.state === 'completed') return existing;
          }
          throw error;
        }
      });
      return await finished(result);
    } catch (error) {
      // Never abort resumable uploads after transient errors. Explicit OSS expiry alone starts anew.
      if (!error.message) error.message = '网络不稳定，已保留上传进度，请重试';
      throw error;
    }
  }

  return async function uploadVideo(filePath, _size, onProgress = () => {}, onStage = () => {}) {
    onStage('preparing');
    await pruneCache();
    const user = await request('/users/me');
    if (!user.id) throw new Error('无法确认登录身份，请重新登录');
    let source;
    try { source = await fileInfo(filePath); }
    catch (_) { throw new Error('本地视频已不可用，请重新选择同一段视频继续上传'); }
    if (!(source.size > 0) || !source.digest) throw new Error('视频文件无效，请重新选择');
    const cacheKey = `${STORAGE_PREFIX}${JSON.stringify([apiBaseUrl, user.id, source.digest, source.size, PROFILE])}`;
    if (active.has(cacheKey)) return active.get(cacheKey);
    const task = run(filePath, source, cacheKey, user.id, onProgress, onStage);
    active.set(cacheKey, task);
    try { return await task; }
    finally { active.delete(cacheKey); }
  };
}

module.exports = { createVideoUploader };
