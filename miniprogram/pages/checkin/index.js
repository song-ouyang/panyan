const { request, uploadVideo } = require('../../utils/api');
const { playFeedback } = require('../../utils/sound');
Page({
  data: { videoPath: '', videoSize: 0, attempts: 1, caption: '', submitting: false, uploadProgress: 0, success: false, milestone: null, pointsEarned: 0 },
  onLoad({ routeId }) { this.routeId = routeId; },
  chooseVideo() { wx.chooseMedia({ count: 1, mediaType: ['video'], maxDuration: 60, success: ({ tempFiles }) => this.setData({ videoPath: tempFiles[0].tempFilePath, videoSize: tempFiles[0].size || 0, uploadProgress: 0 }) }); },
  attempts(e) { this.setData({ attempts: Number(e.detail.value) || 1 }); },
  caption(e) { this.setData({ caption: e.detail.value }); },
  async submit() {
    if (this.data.submitting) return;
    this.setData({ submitting: true });
    try {
      let videoUrl = null;
      if (this.data.videoPath) videoUrl = (await uploadVideo(this.data.videoPath, this.data.videoSize, progress => this.setData({ uploadProgress: progress }))).url;
      const result = await request('/sends', { method: 'POST', data: { routeId: this.routeId, attempts: this.data.attempts, caption: this.data.caption, videoUrl, visibility: 'public' } });
      this.setData({ submitting: false, uploadProgress: 100, success: true, milestone: result.milestone, pointsEarned: result.pointsEarned });
      playFeedback(result.milestone ? 'milestone' : 'success');
    } catch (error) { wx.showToast({ title: error.message, icon: 'none' }); this.setData({ submitting: false }); }
  },
  finish() { wx.navigateBack({ delta: 2 }); }
});
