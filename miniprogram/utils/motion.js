const HAPTIC_INTERVAL_MS = 48;
const HAPTIC_TYPES = {
  selection: 'light',
  success: 'medium',
  milestone: 'medium',
  warning: 'medium',
  error: 'heavy'
};

let lastHapticAt = 0;
let reduceMotion;

function prefersReducedMotion() {
  if (typeof reduceMotion === 'boolean') return reduceMotion;

  try {
    const system = typeof wx.getSystemInfoSync === 'function' ? wx.getSystemInfoSync() : {};
    reduceMotion = Boolean(system.reduceMotionEnabled || system.enableReduceMotion);
  } catch (error) {
    reduceMotion = false;
  }

  return reduceMotion;
}

function motionDuration(duration, reducedDuration = 1) {
  return prefersReducedMotion() ? reducedDuration : duration;
}

function afterPaint(callback, delay = 16) {
  return setTimeout(callback, motionDuration(delay, 0));
}

function haptic(kind = 'selection') {
  const now = Date.now();
  if (now - lastHapticAt < HAPTIC_INTERVAL_MS) return;
  lastHapticAt = now;

  const type = HAPTIC_TYPES[kind] || HAPTIC_TYPES.selection;
  try {
    wx.vibrateShort({ type, fail() {} });
  } catch (error) {
    // Haptics are enhancement-only and must never block the primary action.
  }
}

module.exports = {
  afterPaint,
  haptic,
  motionDuration,
  prefersReducedMotion
};
