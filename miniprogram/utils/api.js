const { API_BASE_URL, DEV_LOGIN, UPLOAD_MODE } = require('./config');
const { createVideoUploader } = require('./video-upload');

let loginPromise = null;

function assertExpectedUser(expectedUserId) {
  if (!expectedUserId) return;
  let userId;
  try {
    const token = wx.getStorageSync('token');
    const encoded = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const bytes = new Uint8Array(wx.base64ToArrayBuffer(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=')));
    // Session payload identifiers are ASCII UUIDs. The API still verifies the JWT signature.
    const payload = JSON.parse(Array.from(bytes, byte => String.fromCharCode(byte)).join(''));
    userId = payload.sub;
  } catch (_) { /* Missing/invalid sessions must not inherit another account's upload. */ }
  if (userId !== expectedUserId) {
    const error = new Error('登录账号已变化，已保留原账号上传进度，请重新选择视频');
    error.statusCode = 403;
    error.code = 'UPLOAD_IDENTITY_CHANGED';
    throw error;
  }
}

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
        else {
          const error = new Error(res.data && res.data.message || '请求失败');
          error.statusCode = res.statusCode;
          error.code = res.data && res.data.code;
          const retryAfter = Object.entries(res.header || {}).find(([key]) => key.toLowerCase() === 'retry-after');
          if (retryAfter) {
            const seconds = Number(retryAfter[1]);
            const delay = Number.isFinite(seconds) ? seconds * 1000 : Date.parse(retryAfter[1]) - Date.now();
            if (Number.isFinite(delay)) error.retryAfterMs = Math.max(0, delay);
          }
          reject(error);
        }
      },
      fail: reject
    });
  });
}

async function request(path, options = {}, retried = false) {
  if (!wx.getStorageSync('token') && path !== '/auth/wechat') await loginOnce();
  assertExpectedUser(options.expectedUserId);
  try {
    const result = await rawRequest(path, options);
    assertExpectedUser(options.expectedUserId);
    return result;
  }
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

function upload(filePath, onProgress, expectedUserId) {
  assertExpectedUser(expectedUserId);
  const token = wx.getStorageSync('token');
  return new Promise((resolve, reject) => wx.uploadFile({
    url: `${API_BASE_URL}/uploads`, filePath, name: 'file',
    header: { authorization: `Bearer ${token}` },
    success(res) {
      try {
        assertExpectedUser(expectedUserId);
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(JSON.parse(res.data));
        else reject(new Error('上传失败'));
      } catch (error) { reject(error); }
    }, fail: reject,
    complete() {}
  }).onProgressUpdate(progress => onProgress && onProgress(progress.progress)));
}

let videoUploader;
function uploadVideo(filePath, size, onProgress, onStage) {
  if (!videoUploader) videoUploader = createVideoUploader({ wx, request, uploadLocal: upload, apiBaseUrl: API_BASE_URL, uploadMode: UPLOAD_MODE });
  return videoUploader(filePath, size, onProgress, onStage);
}

module.exports = { request, login, upload, uploadVideo, API_BASE_URL };
