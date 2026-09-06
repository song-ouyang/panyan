const { request, upload } = require('../../utils/api');
const { haptic } = require('../../utils/motion');
const social = require('../../utils/social-state');
const growth = require('../../utils/growth');
const drafts = require('../../utils/completion-draft');
Page({
  data: { gym: null, imagePath: '', points: [], pointType: 'start', name: '', gradeIndex: 2, grades: ['V0','V1','V2','V3','V4','V5','V6','V7','V8','V9','V10'], color: '', wallZone: '', submitting: false, draftLocked: false, error: '' },
  async onLoad({ gymId }) {
    this.gymId = gymId;
    this._disposed = false;
    try {
      const userId = await social.identity();
      if (this._disposed) return;
      this.owner = growth.session();
      this.draft = drafts.open(userId, 'submission', gymId);
      this.clientRequestId = this.draft.clientRequestId;
      if (this.draft.body) {
        const body = this.draft.body;
        this.setData({ imagePath: body.coverUrl, points: body.points, name: body.name, gradeIndex: Math.max(0, this.data.grades.indexOf(body.grade)), color: body.color, wallZone: body.wallZone || '', draftLocked: true });
      }
      const gym = await request(`/gyms/${gymId}`, { expectedUserId: userId });
      if (!this._disposed && growth.isCurrent(this.owner)) this.setData({ gym });
    } catch (error) { if (!this._disposed) this.setData({ error: error.message || '线路信息没有加载出来，请返回重试' }); }
  },
  onUnload() { this._disposed = true; if (this._returnTimer) clearTimeout(this._returnTimer); },
  newSubmission() {
    if (this.data.submitting || !growth.isCurrent(this.owner)) return;
    wx.showModal({ title: '重新发布线路', content: '上次投稿可能已经成功，请先确认发布记录。继续将创建一份新的线路草稿。', confirmText: '新建草稿', success: result => {
      if (!result.confirm || this._disposed || !growth.isCurrent(this.owner)) return;
      drafts.clear(this.draft);
      this.draft = drafts.open(this.owner.userId, 'submission', this.gymId);
      this.clientRequestId = this.draft.clientRequestId;
      this.setData({ imagePath: '', points: [], name: '', color: '', wallZone: '', draftLocked: false, error: '' });
    } });
  },
  chooseImage() { if (this.data.submitting || this.data.draftLocked) return; wx.chooseMedia({ count: 1, mediaType: ['image'], sourceType: ['camera','album'], success: ({ tempFiles }) => { if (!this._disposed) this.setData({ imagePath: tempFiles[0].tempFilePath, points: [] }); } }); },
  chooseType(e) { const pointType = e.currentTarget.dataset.type; if (pointType === this.data.pointType) return; haptic('selection'); this.setData({ pointType }); },
  addPoint(e) {
    if (!this.data.imagePath || this.data.submitting || this.data.draftLocked) return;
    const query = wx.createSelectorQuery();
    query.select('#wallImage').boundingClientRect(rect => {
      if (!rect) return;
      const x = Math.max(0, Math.min(1, (e.detail.x - rect.left) / rect.width));
      const y = Math.max(0, Math.min(1, (e.detail.y - rect.top) / rect.height));
      const points = [...this.data.points, { x, y, type: this.data.pointType }];
      this.setData({ points, pointType: this.data.pointType === 'start' ? 'hold' : this.data.pointType });
    }).exec();
  },
  undo() { if (!this.data.submitting && !this.data.draftLocked) this.setData({ points: this.data.points.slice(0, -1) }); },
  clear() { if (!this.data.submitting && !this.data.draftLocked) this.setData({ points: [] }); },
  noop() {},
  input(e) { if (!this.data.submitting && !this.data.draftLocked) this.setData({ [e.currentTarget.dataset.key]: e.detail.value }); },
  grade(e) { if (this.data.submitting || this.data.draftLocked) return; const gradeIndex = Number(e.detail.value); if (gradeIndex === this.data.gradeIndex) return; haptic('selection'); this.setData({ gradeIndex }); },
  async submit() {
    if (!this.data.imagePath || !this.data.name.trim() || !this.data.color.trim() || this.data.points.length < 2) return wx.showToast({ title: '请补全照片、信息和至少2个点', icon: 'none' });
    if (!this.data.points.some(point => point.type === 'start')) return wx.showToast({ title: '请至少标记一个起点', icon: 'none' });
    if (!this.data.points.some(point => point.type === 'finish')) return wx.showToast({ title: '请至少标记一个终点', icon: 'none' });
    if (this.data.submitting) return; this.setData({ submitting: true });
    try {
      if (!growth.isCurrent(this.owner) || !this.draft) throw new Error('登录账号已变化，请返回后重新发布');
      if (!this.data.gym) throw new Error('岩馆信息没有加载出来，请返回重试');
      if (!this.draft.body) {
        const { url } = await upload(this.data.imagePath, undefined, this.owner.userId);
        if (this._disposed || !growth.isCurrent(this.owner)) return;
        const activeSet = (this.data.gym.routeSets || []).find(item => item.active);
        const data = { clientRequestId: this.clientRequestId, gymId: this.gymId, routeSetId: activeSet ? activeSet.id : null, name: this.data.name.trim(), grade: this.data.grades[this.data.gradeIndex], color: this.data.color.trim(), coverUrl: url, points: this.data.points };
        const wallZone = this.data.wallZone.trim();
        if (wallZone) data.wallZone = wallZone;
        this.draft = drafts.save(this.draft, { body: data });
        this.setData({ draftLocked: true });
      }
      const result = await request('/submissions', { method: 'POST', data: this.draft.body, expectedUserId: this.owner.userId });
      if (!growth.isCurrent(this.owner)) {
        if (!this._disposed) this.setData({ submitting: false, error: '登录状态已变化，请重新打开页面查看保存结果' });
        return;
      }
      drafts.clear(this.draft);
      growth.accept(this.owner, result.growth);
      if (this._disposed) return;
      haptic('success');
      wx.showToast({ title: '线路已发布' }); this._returnTimer = setTimeout(() => { if (!this._disposed && growth.isCurrent(this.owner)) wx.navigateBack(); }, 700);
    } catch (error) { if (!this._disposed) { this.setData({ submitting: false, error: error.message }); wx.showToast({ title: error.message, icon: 'none' }); } }
  }
});
