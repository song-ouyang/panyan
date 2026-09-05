const { request, uploadVideo } = require('../../utils/api');
const { playFeedback } = require('../../utils/sound');
const { afterPaint, haptic, motionDuration } = require('../../utils/motion');
const { invalidate, invalidatePrefix } = require('../../utils/page-cache');

const PHASE_COPY_DELAY = 80;
const UPLOAD_COPY = {
  preparing: { title: '正在准备视频', description: '正在检查视频和上次的上传进度。' },
  compressing: { title: '正在压缩视频', description: '压缩完成后会自动上传，请稍候。' },
  uploading: { title: '正在上传视频', description: '视频已准备好，上传完成后会自动保存这次打卡。' },
  finishing: { title: '正在确认上传结果', description: '视频分片已传完，正在完成合并。' }
};

Page({
  data: {
    videoPath: '',
    videoSize: 0,
    attempts: 1,
    caption: '',
    phase: 'idle',
    journeyStep: 1,
    journeyComplete: false,
    stageTitle: '先选一段完攀视频',
    stageDescription: '选择 MP4，记录这次完整完攀。',
    stageTextVisible: true,
    submitting: false,
    saveFailed: false,
    submitError: '',
    uploadProgress: 0,
    uploadStage: 'preparing',
    resultVisible: false,
    moderationStatus: '',
    sendId: '',
    milestone: null,
    pointsEarned: 0,
    pendingPoints: 0
  },

  onLoad({ routeId }) {
    this.routeId = routeId;
    this.cachedVideoUrl = '';
    this.cachedVideoOwnerId = '';
    this._disposed = false;
  },

  onShow() {
    if ((this.data.phase === 'pendingReview' || this.data.phase === 'approvedSuccess') && !this.data.resultVisible) {
      this.beginResultMotion(this.data.phase === 'approvedSuccess');
    }
  },

  onHide() { this.clearResultMotion(); },

  onUnload() {
    this._disposed = true;
    this.clearResultMotion();
    this.clearPhaseTimer();
  },

  clearResultMotion() {
    if (this.resultEnterTimer) {
      clearTimeout(this.resultEnterTimer);
      this.resultEnterTimer = null;
    }
  },

  clearPhaseTimer() {
    if (this.phaseTimer) {
      clearTimeout(this.phaseTimer);
      this.phaseTimer = null;
    }
    if (this.phaseResolve) {
      const resolve = this.phaseResolve;
      this.phaseResolve = null;
      resolve();
    }
  },

  phaseCopy(phase, nextData) {
    if (phase === 'uploading') return UPLOAD_COPY[nextData.uploadStage] || UPLOAD_COPY.uploading;
    if (phase === 'saving') {
      return nextData.saveFailed
        ? { title: '视频已上传，保存失败', description: '不用重新上传，点击“重试保存”即可。' }
        : { title: '正在保存打卡', description: '视频已上传，正在记录线路和成绩。' };
    }
    if (phase === 'pendingReview') {
      return {
        title: '已提交，等待审核',
        description: `审核通过后计入 +${nextData.pendingPoints || 0} 分，在“我的”可查看进度。`
      };
    }
    if (phase === 'approvedSuccess') {
      return nextData.milestone
        ? { title: `首次完攀 ${nextData.milestone.grade}`, description: '新的最高难度已经记入你的成长。' }
        : { title: '完攀已记录', description: '这次上墙已经成为看得见的进步。' };
    }
    if (nextData.submitError) return { title: '上传没有完成', description: '视频还在本机，网络恢复后可以直接重试。' };
    if (nextData.videoPath) return { title: '视频已经选好', description: '补充尝试次数和感受，然后上传提交。' };
    return { title: '先选一段完攀视频', description: '选择 MP4，记录这次完整完攀。' };
  },

  transitionPhase(phase, extra = {}) {
    this.clearPhaseTimer();
    const nextData = { ...this.data, ...extra, phase };
    const copy = this.phaseCopy(phase, nextData);
    const journeyStep = phase === 'idle' ? (nextData.videoPath ? 2 : 1) : (phase === 'uploading' || phase === 'saving' ? 2 : 3);
    const journeyComplete = phase === 'pendingReview' || phase === 'approvedSuccess';

    return new Promise((resolve) => {
      this.setData({
        ...extra,
        phase,
        journeyStep,
        journeyComplete,
        stageTextVisible: false
      }, () => {
        const apply = () => {
          this.phaseTimer = null;
          this.phaseResolve = null;
          if (this._disposed) return resolve();
          this.setData({
            stageTitle: copy.title,
            stageDescription: copy.description,
            stageTextVisible: true
          }, resolve);
        };
        const delay = motionDuration(PHASE_COPY_DELAY, 0);
        if (delay) {
          this.phaseResolve = resolve;
          this.phaseTimer = setTimeout(apply, delay);
        }
        else apply();
      });
    });
  },

  beginResultMotion(approved) {
    this.clearResultMotion();
    this.resultEnterTimer = afterPaint(() => {
      this.resultEnterTimer = null;
      if (this._disposed) return;
      this.setData({ resultVisible: true }, () => {
        if (!approved) return haptic('selection');
        const feedbackType = this.data.milestone ? 'milestone' : 'success';
        haptic(feedbackType);
        playFeedback(feedbackType);
      });
    });
  },

  chooseVideo() {
    if (this.data.submitting) return;
    wx.chooseMedia({
      count: 1,
      mediaType: ['video'],
      maxDuration: 60,
      success: ({ tempFiles }) => {
        const file = tempFiles && tempFiles[0];
        if (!file || !/\.mp4(?:$|[?#])/i.test(file.tempFilePath || '')) {
          wx.showToast({ title: '请选择 MP4 视频', icon: 'none' });
          return;
        }
        this.cachedVideoUrl = '';
        this.cachedVideoOwnerId = '';
        this.setData({
          videoPath: file.tempFilePath,
          videoSize: file.size || 0,
          uploadProgress: 0,
          saveFailed: false,
          submitError: ''
        }, () => this.transitionPhase('idle'));
        haptic('selection');
      }
    });
  },

  noop() {},

  attempts(e) { this.setData({ attempts: Number(e.detail.value) || 1 }); },

  caption(e) { this.setData({ caption: e.detail.value }); },

  primaryAction() {
    if (!this.data.videoPath) return this.chooseVideo();
    return this.submit();
  },

  async submit() {
    if (this.data.submitting) return;
    if (!this.data.videoPath) {
      wx.showToast({ title: '请先选择 MP4 完攀视频', icon: 'none' });
      return;
    }
    if (!this.routeId) {
      wx.showToast({ title: '线路信息不完整，请返回重试', icon: 'none' });
      return;
    }

    this.setData({ submitting: true, saveFailed: false, submitError: '' });
    try {
      if (!this.cachedVideoUrl) {
        await this.transitionPhase('uploading', { uploadProgress: 0, uploadStage: 'preparing' });
        if (this._disposed) return;
        const uploaded = await uploadVideo(
          this.data.videoPath,
          this.data.videoSize,
          uploadProgress => {
            if (!this._disposed) this.setData({ uploadProgress });
          },
          uploadStage => {
            if (this._disposed) return;
            const copy = UPLOAD_COPY[uploadStage] || UPLOAD_COPY.uploading;
            this.setData({ uploadStage, stageTitle: copy.title, stageDescription: copy.description });
          }
        );
        if (this._disposed) return;
        this.cachedVideoUrl = uploaded.url;
        this.cachedVideoOwnerId = uploaded.ownerId;
      }

      await this.transitionPhase('saving', { uploadProgress: 100, saveFailed: false });
      if (this._disposed) return;
      if (!this.cachedVideoOwnerId) throw new Error('无法确认上传账号，请重新选择视频');
      const result = await request('/sends', {
        method: 'POST',
        expectedUserId: this.cachedVideoOwnerId,
        data: {
          routeId: this.routeId,
          attempts: this.data.attempts,
          caption: this.data.caption,
          videoUrl: this.cachedVideoUrl,
          visibility: 'public'
        }
      });
      if (this._disposed) return;

      const moderationStatus = result.moderationStatus || (result.send && result.send.moderation_status) || 'approved';
      const sendId = result.sendId || (result.send && result.send.id) || '';
      const pointsEarned = Number(result.pointsEarned || 0);
      const pendingPoints = Number(result.pendingPoints || 0);
      const finalPhase = moderationStatus === 'pending' ? 'pendingReview' : 'approvedSuccess';
      const checkinResult = {
        routeId: this.routeId,
        sendId,
        status: moderationStatus,
        points: moderationStatus === 'pending' ? pendingPoints : pointsEarned,
        pendingPoints,
        milestone: result.milestone || null
      };
      wx.setStorageSync('lastCheckinResult', checkinResult);
      invalidate('profile:overview');
      invalidatePrefix('profile:dashboard:');
      if (moderationStatus === 'approved') {
        invalidate('feed:public');
        invalidate('ranking:routes');
        invalidatePrefix('ranking:users:');
      }

      await this.transitionPhase(finalPhase, {
        submitting: false,
        resultVisible: false,
        moderationStatus,
        sendId,
        milestone: result.milestone || null,
        pointsEarned,
        pendingPoints
      });
      this.beginResultMotion(finalPhase === 'approvedSuccess');
    } catch (error) {
      if (this._disposed) return;
      const saveFailed = Boolean(this.cachedVideoUrl);
      await this.transitionPhase(saveFailed ? 'saving' : 'idle', {
        submitting: false,
        saveFailed,
        submitError: error.message || '提交失败'
      });
      wx.showToast({ title: error.message || '提交失败，请重试', icon: 'none' });
      haptic('error');
    }
  },

  viewRoute() {
    this.clearResultMotion();
    wx.navigateBack({ delta: 1 });
  },

  backToGym() {
    this.clearResultMotion();
    wx.navigateBack({ delta: 2 });
  }
});
