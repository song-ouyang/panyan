const { request, upload } = require('../../utils/api');
const { haptic } = require('../../utils/motion');
const { invalidate } = require('../../utils/page-cache');
Page({
  data: { nickname: '', avatarUrl: '', bio: '', saving: false },
  async onLoad() { const me = await request('/users/me'); this.setData({ nickname: me.nickname, avatarUrl: me.avatar_url || '', bio: me.bio || '' }); },
  input(e) { this.setData({ [e.currentTarget.dataset.key]: e.detail.value }); },
  chooseAvatar(e) { this.setData({ avatarUrl: e.detail.avatarUrl }); },
  async save() {
    if (!this.data.nickname.trim() || this.data.saving) return wx.showToast({ title: '请填写昵称', icon: 'none' });
    this.setData({ saving: true });
    try {
      let avatarUrl = this.data.avatarUrl || null;
      if (avatarUrl && !/^https?:/.test(avatarUrl)) avatarUrl = (await upload(avatarUrl)).url;
      await request('/users/me', { method: 'PATCH', data: { nickname: this.data.nickname.trim(), avatarUrl, bio: this.data.bio.trim() || null } });
      invalidate('profile:overview');
      haptic('success');
      wx.showToast({ title: '已保存' }); setTimeout(() => wx.navigateBack(), 500);
    } catch (error) { this.setData({ saving: false }); wx.showToast({ title: error.message, icon: 'none' }); }
  }
});
