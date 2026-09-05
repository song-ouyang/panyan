const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { createVideoUploader } = require('../utils/video-upload');

function error(statusCode, code) {
  return Object.assign(new Error(code || 'network unavailable'), { statusCode, code });
}

function harness(options = {}) {
  const source = Buffer.alloc(80, 7);
  const output = Buffer.alloc(options.outputSize || 23, 9);
  const state = {
    files: new Map([['/original.mp4', source]]), storage: new Map(), sessions: new Map(),
    requests: [], puts: [], sleeps: [], compression: [], copies: [], local: [], events: [],
    user: 'user-one', clock: 100000, concurrent: 0, peak: 0, nextId: 0,
    failPut: null, failStatus: null, failComplete: null
  };
  const info = path => {
    const bytes = state.files.get(path);
    if (!bytes) throw new Error('no such file');
    return { size: bytes.length, digest: createHash('sha1').update(bytes).digest('hex') };
  };
  const fs = {
    copyFile({ srcPath, destPath, success, fail }) {
      const bytes = state.files.get(srcPath);
      if (!bytes) return fail(error());
      state.copies.push({ srcPath, destPath });
      state.files.set(destPath, Buffer.from(bytes));
      success({});
    },
    unlink({ filePath, success }) { state.files.delete(filePath); success({}); },
    readFile({ filePath, position, length, success, fail }) {
      const bytes = state.files.get(filePath);
      if (!bytes) return fail(error());
      const chunk = bytes.subarray(position, position + length);
      success({ data: chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength) });
    }
  };
  const platform = {
    env: { USER_DATA_PATH: '/saved' },
    getFileSystemManager: () => fs,
    getStorageInfoSync: () => ({ keys: Array.from(state.storage.keys()) }),
    getStorageSync: key => state.storage.get(key),
    setStorageSync: (key, value) => state.storage.set(key, structuredClone(value)),
    removeStorageSync: key => state.storage.delete(key),
    getFileInfo({ filePath, success, fail }) {
      try { success(info(filePath)); } catch (cause) { fail(cause); }
    },
    getVideoInfo({ src, success }) {
      success({ width: 3840, height: 2160, fps: 60, bitrate: 12000, duration: src.startsWith('/compressed') ? (options.outputDuration || 60) : 60, type: src.startsWith('/compressed') ? (options.outputType || 'mp4') : 'mp4' });
    },
    compressVideo({ success, fail, ...params }) {
      state.compression.push(params);
      if (options.compressFailure) return fail(error());
      const path = `/compressed-${state.compression.length}.mp4`;
      state.files.set(path, Buffer.from(output));
      // Deliberately incorrect kB metadata proves the uploader reads actual file bytes.
      success({ tempFilePath: path, size: 123456 });
    },
    request({ url, data, success, fail }) {
      const [, uploadId, rawNumber, version] = url.split('/');
      const number = Number(rawNumber);
      const session = state.sessions.get(uploadId);
      const entry = { uploadId, number, version: Number(version), bytes: Buffer.from(data) };
      state.puts.push(entry);
      state.concurrent += 1;
      state.peak = Math.max(state.peak, state.concurrent);
      setImmediate(() => {
        state.concurrent -= 1;
        const problem = state.failPut && state.failPut(entry);
        if (problem) {
          if (problem.statusCode) return success({ statusCode: problem.statusCode });
          return fail(problem);
        }
        const part = { number, etag: `etag-${number}`, size: data.byteLength };
        session.parts.set(number, part);
        success({ statusCode: 200, header: { eTaG: part.etag } });
      });
    }
  };
  const request = async (path, options = {}) => {
    const data = options.data;
    state.requests.push({ path, data, expectedUserId: options.expectedUserId });
    if (path === '/users/me') return { id: state.user };
    if (path.endsWith('/init')) {
      const uploadId = `upload-${++state.nextId}`;
      state.sessions.set(uploadId, { parts: new Map(), versions: new Map(), size: data.size });
      return { key: `videos/${state.user}/${uploadId}.mp4`, uploadId, partSize: 5 };
    }
    const session = state.sessions.get(data.uploadId);
    if (path.endsWith('/status')) {
      if (state.failStatus) throw state.failStatus;
      return session.completed
        ? { state: 'completed', url: `https://oss/${data.uploadId}.mp4`, size: session.size }
        : { state: 'uploading', parts: Array.from(session.parts.values()) };
    }
    if (path.endsWith('/part-url')) {
      const version = (session.versions.get(data.partNumber) || 0) + 1;
      session.versions.set(data.partNumber, version);
      return { url: `oss/${data.uploadId}/${data.partNumber}/${version}` };
    }
    if (path.endsWith('/complete')) {
      state.events.push('complete');
      const result = { url: `https://oss/${data.uploadId}.mp4`, size: session.size };
      session.completed = true;
      if (state.failComplete) throw state.failComplete;
      return result;
    }
    throw new Error(`Unexpected API: ${path}`);
  };
  const uploader = overrides => createVideoUploader({
    wx: platform, request, apiBaseUrl: 'https://api.example/api', uploadMode: 'oss',
    uploadLocal: async (filePath, onProgress) => {
      state.local.push({ filePath, ...info(filePath) });
      onProgress(100);
      return { url: '/local/video.mp4' };
    },
    sleep: async delay => { state.sleeps.push(delay); }, now: () => state.clock++, random: () => 0,
    ...overrides
  });
  const count = suffix => state.requests.filter(item => item.path.endsWith(suffix)).length;
  return { state, platform, uploader, count, source, output };
}

test('compresses before upload, uses actual bytes, bounds concurrency to three and only reaches 100 after completion', async () => {
  const { state, uploader, output } = harness();
  const stages = [];
  const result = await uploader()('/original.mp4', 999999, progress => state.events.push(progress), stage => stages.push(stage));
  assert.match(result.url, /upload-1/);
  assert.equal(result.ownerId, 'user-one');
  assert.equal(state.peak, 3);
  assert.deepEqual(state.compression[0], { src: '/original.mp4', bitrate: 2500, fps: 30, resolution: 0.5 });
  const init = state.requests.find(item => item.path.endsWith('/init'));
  assert.deepEqual(init.data, { filename: 'send.mp4', mimeType: 'video/mp4', size: output.length });
  const transmitted = Buffer.concat(state.puts.sort((a, b) => a.number - b.number).map(part => part.bytes));
  assert.deepEqual(transmitted, output);
  assert.deepEqual(stages, ['preparing', 'compressing', 'uploading', 'finishing']);
  assert.equal(state.events.at(-1), 100);
  assert.ok(state.events.indexOf(100) > state.events.indexOf('complete'));
  const progress = state.events.filter(item => typeof item === 'number');
  assert.deepEqual(progress, progress.slice().sort((a, b) => a - b));
  assert.deepEqual(state.requests.find(item => item.path.endsWith('/complete')).data.parts.map(part => part.number), [1, 2, 3, 4, 5]);
  assert.ok(state.files.has('/original.mp4'));
  assert.equal([...state.files.keys()].filter(path => path.startsWith('/saved/')).length, 1);
  assert.ok(state.requests.filter(item => item.path.startsWith('/uploads/')).every(item => item.expectedUserId === 'user-one'));
});

test('retries expired signatures with a newly signed URL and exponential backoff', async () => {
  const { state, uploader } = harness();
  state.failPut = part => part.number === 2 && part.version < 3 ? error(403) : null;
  await uploader()('/original.mp4', 80);
  assert.deepEqual(state.puts.filter(part => part.number === 2).map(part => part.version), [1, 2, 3]);
  assert.deepEqual(state.sleeps, [500, 1000]);
  assert.equal(state.peak, 3);
});

test('restart and reselection resume only missing OSS parts without recompression or init', async () => {
  const { state, uploader, count, source } = harness();
  state.failPut = part => part.number === 2 ? error() : null;
  await assert.rejects(uploader()('/original.mp4', 80));
  assert.equal(state.concurrent, 0);
  assert.equal(count('/abort'), 0);
  const checkpoint = [...state.storage.values()][0];
  assert.ok(checkpoint.task.uploadId);
  assert.ok(state.files.has(checkpoint.filePath));
  const previousPuts = state.puts.length;
  state.failPut = null;
  state.files.set('/reselected.mp4', Buffer.from(source));
  // Simulate a token refresh and a new JS runtime, keeping account identity and persistent storage.
  state.storage.set('token', 'a-refreshed-token');
  await uploader()('/reselected.mp4', 1);
  assert.equal(count('/init'), 1);
  assert.equal(count('/status'), 1);
  assert.equal(state.compression.length, 1);
  assert.deepEqual(state.puts.slice(previousPuts).map(part => part.number), [2]);
});

test('OSS status recovers an acknowledged part missing from the local checkpoint', async () => {
  const { state, uploader } = harness();
  state.failPut = part => part.number === 2 ? error() : null;
  await assert.rejects(uploader()('/original.mp4', 80));
  state.sessions.get('upload-1').parts.set(2, { number: 2, etag: 'accepted-before-connection-lost', size: 5 });
  state.failPut = null;
  const sent = state.puts.length;
  await uploader()('/original.mp4', 80);
  assert.equal(state.puts.length, sent);
});

test('only explicit UPLOAD_NOT_FOUND restarts a session; other 404/403/503 responses preserve it', async () => {
  for (const failure of [error(404, 'ROUTE_NOT_FOUND'), error(403), error(503), error(404, 'UPLOAD_NOT_FOUND')]) {
    const { state, uploader, count } = harness();
    state.failPut = part => part.number === 2 ? error() : null;
    await assert.rejects(uploader()('/original.mp4', 80));
    state.failPut = null;
    state.failStatus = failure;
    if (failure.code === 'UPLOAD_NOT_FOUND') {
      await uploader()('/original.mp4', 80);
      assert.equal(count('/init'), 2);
    } else {
      await assert.rejects(uploader()('/original.mp4', 80));
      assert.equal(count('/init'), 1);
      assert.equal([...state.storage.values()][0].task.uploadId, 'upload-1');
    }
    assert.equal(count('/abort'), 0);
  }
});

test('recovers a completed upload when its completion response was lost', async () => {
  const { state, uploader, count } = harness();
  state.failComplete = error();
  const result = await uploader()('/original.mp4', 80);
  assert.match(result.url, /upload-1/);
  assert.equal(count('/complete'), 1);
  assert.equal(count('/status'), 1);
  await uploader()('/original.mp4', 80);
  assert.equal(count('/init'), 1);
  assert.equal(count('/status'), 2);
});

test('a previously completed object is checked remotely and uploaded again if OSS removed it', async () => {
  const { state, uploader, count } = harness();
  await uploader()('/original.mp4', 80);
  state.failStatus = error(404, 'UPLOAD_NOT_FOUND');
  const result = await uploader()('/original.mp4', 80);
  assert.match(result.url, /upload-2/);
  assert.equal(count('/status'), 1);
  assert.equal(count('/init'), 2);
  assert.equal(state.compression.length, 1);
});

test('isolation uses account, API environment and file content instead of filename or token', async () => {
  const { state, uploader, count } = harness();
  await uploader()('/original.mp4', 80);
  state.user = 'user-two';
  await uploader()('/original.mp4', 80);
  await uploader({ apiBaseUrl: 'https://other-api.example/api' })('/original.mp4', 80);
  state.files.set('/original.mp4', Buffer.alloc(80, 8));
  await uploader()('/original.mp4', 80);
  assert.equal(count('/init'), 4);
  assert.equal(state.compression.length, 4);
});

test('compression failure and unsupported output fail visibly before any upload', async () => {
  for (const options of [{ compressFailure: true }, { outputType: 'mov' }, { outputDuration: 30 }]) {
    const { state, uploader, count } = harness(options);
    await assert.rejects(uploader()('/original.mp4', 80), /压缩或保存失败/);
    assert.equal(count('/init'), 0);
    assert.equal(state.puts.length, 0);
  }
});

test('successful compression that grows the clip uses smaller original bytes while preserving the selected file', async () => {
  const { state, source, uploader } = harness({ outputSize: 100 });
  await uploader()('/original.mp4', 80);
  assert.equal(state.requests.find(item => item.path.endsWith('/init')).data.size, source.length);
  const transmitted = Buffer.concat(state.puts.sort((a, b) => a.number - b.number).map(part => part.bytes));
  assert.deepEqual(transmitted, source);
  assert.deepEqual(state.files.get('/original.mp4'), source);
});

test('local development upload also receives the compressed artifact and true byte size', async () => {
  const { state, uploader, count, output } = harness();
  const result = await uploader({ uploadMode: 'local' })('/original.mp4', 80);
  assert.equal(result.url, '/local/video.mp4');
  assert.equal(result.ownerId, 'user-one');
  assert.equal(state.local[0].size, output.length);
  assert.match(state.local[0].filePath, /\.mp4$/);
  assert.equal(count('/init'), 0);
});

test('invalid local cached bytes force preparation and a new session instead of mixing different video bytes', async () => {
  const { state, uploader, count } = harness();
  state.failPut = part => part.number === 2 ? error() : null;
  await assert.rejects(uploader()('/original.mp4', 80));
  const [key, checkpoint] = [...state.storage.entries()][0];
  state.files.set(checkpoint.filePath, Buffer.alloc(23, 1));
  checkpoint.digest = 'a-different-previous-compressed-version';
  state.storage.set(key, checkpoint);
  state.failPut = null;
  await uploader()('/original.mp4', 80);
  assert.equal(state.compression.length, 2);
  assert.equal(count('/init'), 2);
});

test('checkpoint storage failure removes the new prepared artifact and sends no video', async () => {
  const { state, platform, uploader, count } = harness();
  platform.setStorageSync = () => { throw new Error('quota exceeded'); };
  await assert.rejects(uploader()('/original.mp4', 80), /无法保存上传进度/);
  assert.equal(count('/init'), 0);
  assert.deepEqual([...state.files.keys()], ['/original.mp4']);
});

test('expired local prepared files are removed after seven days', async () => {
  const { state, uploader, count } = harness();
  await uploader()('/original.mp4', 80);
  const previousPath = [...state.storage.values()][0].filePath;
  state.clock += 8 * 24 * 60 * 60 * 1000;
  await uploader()('/original.mp4', 80);
  assert.equal(state.files.has(previousPath), false);
  assert.equal(count('/init'), 2);
});
