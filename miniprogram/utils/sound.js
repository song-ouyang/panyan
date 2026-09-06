let currentAudio = null;

function badgeSoundEnabled() {
  try { return wx.getStorageSync('badgeSoundEnabled') === true; } catch (_) { return false; }
}

function setBadgeSoundEnabled(enabled) { wx.setStorageSync('badgeSoundEnabled', Boolean(enabled)); }

function stopFeedback() {
  const audio = currentAudio;
  currentAudio = null;
  if (audio) { try { audio.destroy(); } catch (_) {} }
}

function playFeedback(type = 'success') {
  try {
    if (type === 'badge' && !badgeSoundEnabled()) return;
    stopFeedback();
    const audio = wx.createInnerAudioContext({ useWebAudioImplement: true });
    currentAudio = audio;
    audio.obeyMuteSwitch = true;
    audio.volume = type === 'badge' ? 0.41085 : 0.72;
    audio.src = type === 'badge' ? '/growth/assets/badge-earned.mp3' : type === 'milestone'
      ? '/assets/sounds/grade-milestone.wav'
      : '/assets/sounds/send-success.wav';
    const cleanup = () => { if (currentAudio === audio) stopFeedback(); };
    audio.onEnded(cleanup);
    audio.onError(cleanup);
    audio.play();
  } catch (_) {}
}

module.exports = { playFeedback, stopFeedback, badgeSoundEnabled, setBadgeSoundEnabled };
