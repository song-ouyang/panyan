const { API_BASE_URL, DEV_LOGIN, UPLOAD_MODE } = require('./config');

let loginPromise = null;

function rawRequest(path, options = {}) {
  const token = wx.getStorageSync('token');
  return new Promise((resolve, reject) => {
    wx.request({
      url: `${API_BASE_URL}${path}`,
      method: options.method || 'GET',
      data: options.data,
      header: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(res.data);
        else { const error = new Error(res.data && res.data.message || '请求失败'); error.statusCode = res.statusCode; reject(error); }
      },
      fail: reject
    });
  });
}

async function request(path, options = {}, retried = false) {
  if (!wx.getStorageSync('token') && path !== '/auth/wechat') await loginOnce();
  try { return await rawRequest(path, options); }
  catch (error) {
    if (error.statusCode === 401 && !retried && path !== '/auth/wechat') {
      wx.removeStorageSync('token');
      await loginOnce();
      return request(path, options, true);
    }
    throw error;
  }
}

function loginOnce() {
  if (!loginPromise) {
    loginPromise = login().then(
      (value) => { loginPromise = null; return value; },
      (error) => { loginPromise = null; throw error; },
    );
  }
  return loginPromise;
}

async function login() {
  let code;
  if (DEV_LOGIN) {
    let deviceId = wx.getStorageSync('devDeviceId');
    if (!deviceId) {
      deviceId = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
      wx.setStorageSync('devDeviceId', deviceId);
    }
    code = `dev:${deviceId}`;
  } else {
    const result = await new Promise((resolve, reject) => wx.login({ success: resolve, fail: reject }));
    code = result.code;
  }
  const data = await rawRequest('/auth/wechat', { method: 'POST', data: { code } });
  wx.setStorageSync('token', data.token);
  return data;
}

function upload(filePath, onProgress) {
  const token = wx.getStorageSync('token');
  return new Promise((resolve, reject) => wx.uploadFile({
    url: `${API_BASE_URL}/uploads`, filePath, name: 'file',
    header: { authorization: `Bearer ${token}` },
    success(res) {
      if (res.statusCode >= 200 && res.statusCode < 300) resolve(JSON.parse(res.data));
      else reject(new Error('上传失败'));
    }, fail: reject,
    complete() {}
  }).onProgressUpdate(progress => onProgress && onProgress(progress.progress)));
}

function readChunk(filePath, position, length) {
  return new Promise((resolve, reject) => wx.getFileSystemManager().readFile({ filePath, position, length, success: res => resolve(res.data), fail: reject }));
}

function putPart(url, data) {
  return new Promise((resolve, reject) => wx.request({ url, method: 'PUT', data, header: { 'content-type': 'application/octet-stream' }, success: res => {
    if (res.statusCode < 200 || res.statusCode >= 300) return reject(new Error(`分片上传失败(${res.statusCode})`));
    const etag = res.header.ETag || res.header.Etag || res.header.etag;
    if (!etag) return reject(new Error('OSS未返回ETag，请检查Bucket跨域暴露配置'));
    resolve(etag);
  }, fail: reject }));
}

async function uploadVideo(filePath, size, onProgress) {
  if (UPLOAD_MODE !== 'oss') return upload(filePath, onProgress);
  const task = await request('/uploads/multipart/init', { method: 'POST', data: { filename: 'send.mp4', mimeType: 'video/mp4', size } });
  const parts = [];
  try {
    const total = Math.ceil(size / task.partSize);
    for (let index = 0; index < total; index += 1) {
      const partNumber = index + 1;
      const position = index * task.partSize;
      const length = Math.min(task.partSize, size - position);
      const data = await readChunk(filePath, position, length);
      const signed = await request('/uploads/multipart/part-url', { method: 'POST', data: { key: task.key, uploadId: task.uploadId, partNumber } });
      let etag; let lastError;
      for (let attempt = 0; attempt < 3 && !etag; attempt += 1) {
        try { etag = await putPart(signed.url, data); } catch (error) { lastError = error; }
      }
      if (!etag) throw lastError || new Error('分片上传失败');
      parts.push({ number: partNumber, etag });
      onProgress && onProgress(Math.round((partNumber / total) * 100));
    }
    return await request('/uploads/multipart/complete', { method: 'POST', data: { key: task.key, uploadId: task.uploadId, parts } });
  } catch (error) {
    request('/uploads/multipart/abort', { method: 'POST', data: { key: task.key, uploadId: task.uploadId } }).catch(() => {});
    throw error;
  }
}

module.exports = { request, login, upload, uploadVideo, API_BASE_URL };
