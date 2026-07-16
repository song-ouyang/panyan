let currentAudio = null;

function playFeedback(type = 'success') {
  try {
    if (currentAudio) currentAudio.destroy();
    currentAudio = wx.createInnerAudioContext({ useWebAudioImplement: true });
    currentAudio.obeyMuteSwitch = true;
    currentAudio.volume = 0.72;
    currentAudio.src = type === 'milestone' ? '/assets/sounds/milestone.wav' : '/assets/sounds/success.wav';
    currentAudio.onEnded(() => { currentAudio.destroy(); currentAudio = null; });
    currentAudio.onError(() => { if (currentAudio) currentAudio.destroy(); currentAudio = null; });
    currentAudio.play();
  } catch (_) {}
}

module.exports = { playFeedback };
