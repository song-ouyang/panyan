const { request } = require('../../utils/api');
const { haptic } = require('../../utils/motion');
const sound = require('../../utils/sound');
Page({
  data: { badgeSoundEnabled: false },
  onShow() { this.setData({ badgeSoundEnabled: sound.badgeSoundEnabled() }); },
  changeBadgeSound(event) { const enabled = Boolean(event.detail.value); sound.setBadgeSoundEnabled(enabled); this.setData({ badgeSoundEnabled: enabled }); if (!enabled) sound.stopFeedback(); },
  privacy() { wx.navigateTo({ url: '/pages/legal/privacy' }); },
  terms() { wx.navigateTo({ url: '/pages/legal/terms' }); },
  clearCache() { wx.removeStorageSync('token'); haptic('success'); wx.showToast({ title: '登录缓存已清除' }); },
  deleteAccount() { wx.showModal({ title: '注销账号', content: '注销后，个人资料、完攀记录、动态、评论、好友和约爬数据将被永久删除，无法恢复。', confirmText: '继续注销', confirmColor: '#c33', success: res => { if (!res.confirm) return; wx.showModal({ title: '再次确认', content: '确定永久删除全部数据吗？', confirmText: '永久删除', confirmColor: '#c33', success: async final => { if (!final.confirm) return; await request('/users/me', { method: 'DELETE' }); haptic('warning'); wx.clearStorageSync(); wx.reLaunch({ url: '/pages/gyms/index' }); } }); } }); }
});
