const { request, upload } = require('../../utils/api');

Page({
  data: { showProfile: false, nickname: '', avatarUrl: '', saving: false },
  onReady() { this.prepare(); },
  onUnload() { if (this.timer) clearTimeout(this.timer); },
  async prepare() {
    try {
      const me = await request('/users/me');
      const incomplete = !me.avatar_url || !me.nickname || me.nickname === '岩友';
      if (incomplete && !wx.getStorageSync('profilePromptSkipped')) return this.setData({ showProfile: true, nickname: me.nickname === '岩友' ? '' : me.nickname, avatarUrl: me.avatar_url || '' });
    } catch (error) { console.error('[splash] profile check failed', error); }
    this.timer = setTimeout(() => this.enter(), 1200);
  },
  chooseAvatar(e) { this.setData({ avatarUrl: e.detail.avatarUrl }); },
  nickname(e) { this.setData({ nickname: e.detail.value }); },
  async saveProfile() {
    if (!this.data.nickname.trim()) return wx.showToast({ title: '请输入昵称', icon: 'none' });
    if (!this.data.avatarUrl) return wx.showToast({ title: '请选择头像', icon: 'none' });
    this.setData({ saving: true });
    try {
      let avatarUrl = this.data.avatarUrl;
      if (!/^https?:/.test(avatarUrl)) avatarUrl = (await upload(avatarUrl)).url;
      await request('/users/me', { method: 'PATCH', data: { nickname: this.data.nickname.trim(), avatarUrl, bio: null } });
      this.setData({ saving: false, showProfile: false }); wx.showToast({ title: '欢迎加入', icon: 'success' }); this.enter();
    } catch (error) { this.setData({ saving: false }); wx.showToast({ title: error.message || '资料保存失败', icon: 'none' }); }
  },
  skip() { wx.setStorageSync('profilePromptSkipped', true); this.setData({ showProfile: false }); this.enter(); },
  enter() { if (this.entered || this.data.showProfile) return; this.entered = true; if (this.timer) clearTimeout(this.timer); wx.switchTab({ url: '/pages/gyms/index' }); }
});
