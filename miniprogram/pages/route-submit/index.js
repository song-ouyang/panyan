const { request, upload } = require('../../utils/api');
Page({
  data: { gym: null, imagePath: '', points: [], pointType: 'start', name: '', gradeIndex: 2, grades: ['V0','V1','V2','V3','V4','V5','V6','V7','V8','V9','V10'], color: '', wallZone: '', submitting: false },
  async onLoad({ gymId }) { this.gymId = gymId; this.setData({ gym: await request(`/gyms/${gymId}`) }); },
  chooseImage() { wx.chooseMedia({ count: 1, mediaType: ['image'], sourceType: ['camera','album'], success: ({ tempFiles }) => this.setData({ imagePath: tempFiles[0].tempFilePath, points: [] }) }); },
  chooseType(e) { this.setData({ pointType: e.currentTarget.dataset.type }); },
  addPoint(e) {
    if (!this.data.imagePath) return;
    const query = wx.createSelectorQuery();
    query.select('#wallImage').boundingClientRect(rect => {
      if (!rect) return;
      const x = Math.max(0, Math.min(1, (e.detail.x - rect.left) / rect.width));
      const y = Math.max(0, Math.min(1, (e.detail.y - rect.top) / rect.height));
      const points = [...this.data.points, { x, y, type: this.data.pointType }];
      this.setData({ points, pointType: this.data.pointType === 'start' ? 'hold' : this.data.pointType });
    }).exec();
  },
  undo() { this.setData({ points: this.data.points.slice(0, -1) }); },
  clear() { this.setData({ points: [] }); },
  noop() {},
  input(e) { this.setData({ [e.currentTarget.dataset.key]: e.detail.value }); },
  grade(e) { this.setData({ gradeIndex: Number(e.detail.value) }); },
  async submit() {
    if (!this.data.imagePath || !this.data.name.trim() || !this.data.color.trim() || this.data.points.length < 2) return wx.showToast({ title: '请补全照片、信息和至少2个点', icon: 'none' });
    if (this.data.submitting) return; this.setData({ submitting: true });
    try {
      const { url } = await upload(this.data.imagePath);
      const activeSet = (this.data.gym.routeSets || []).find(item => item.active);
      await request('/submissions', { method: 'POST', data: { gymId: this.gymId, routeSetId: activeSet ? activeSet.id : null, name: this.data.name.trim(), grade: this.data.grades[this.data.gradeIndex], color: this.data.color.trim(), wallZone: this.data.wallZone.trim() || null, coverUrl: url, points: this.data.points } });
      wx.showToast({ title: '已提交审核' }); setTimeout(() => wx.navigateBack(), 700);
    } catch (error) { this.setData({ submitting: false }); wx.showToast({ title: error.message, icon: 'none' }); }
  }
});
