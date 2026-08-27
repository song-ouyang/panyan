const entries = Object.create(null);
const pending = Object.create(null);

function read(key, ttl = 0) {
  const entry = entries[key];
  if (!entry) return null;
  const age = Math.max(0, Date.now() - entry.updatedAt);
  return {
    value: entry.value,
    updatedAt: entry.updatedAt,
    age,
    fresh: ttl > 0 && age < ttl,
  };
}

function write(key, value) {
  entries[key] = { value, updatedAt: Date.now() };
  return value;
}

function loadOnce(key, loader) {
  if (pending[key]) return pending[key];

  let task;
  task = Promise.resolve()
    .then(loader)
    .then(
      (value) => {
        if (pending[key] === task) delete pending[key];
        return value;
      },
      (error) => {
        if (pending[key] === task) delete pending[key];
        throw error;
      },
    );
  pending[key] = task;
  return task;
}

function invalidate(key) {
  if (!key) return;
  delete entries[key];
  delete pending[key];
}

function invalidateMany(keys) {
  if (!Array.isArray(keys)) return;
  keys.forEach(invalidate);
}

function invalidatePrefix(prefix) {
  if (typeof prefix !== 'string' || !prefix) return;

  Object.keys(entries).forEach((key) => {
    if (key.indexOf(prefix) === 0) delete entries[key];
  });
  Object.keys(pending).forEach((key) => {
    if (key.indexOf(prefix) === 0) delete pending[key];
  });
}

module.exports = {
  read,
  write,
  loadOnce,
  invalidate,
  invalidateMany,
  invalidatePrefix,
};
