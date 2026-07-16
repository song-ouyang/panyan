const { request, upload } = require('../../utils/api');
Page({
  data: { items: [], loading: true, showComposer: false, draft: '', draftImages: [], publishing: false },
  onShow() { this.load(); },
  async load() { const data = await request('/sends/feed'); const items = data.items.map(item => ({ ...item, sent_at_text: this.relativeTime(item.sent_at) })); this.setData({ items, loading: false }); },
  relativeTime(value) { const diff = Math.max(0, Date.now() - new Date(value).getTime()); if (diff < 60000) return '刚刚'; if (diff < 3600000) return `${Math.floor(diff / 60000)}分钟前`; if (diff < 86400000) return `${Math.floor(diff / 3600000)}小时前`; return `${Math.floor(diff / 86400000)}天前`; },
  async like(e) { const { id, liked } = e.currentTarget.dataset; await request(`/sends/${id}/like`, { method: liked ? 'DELETE' : 'POST' }); this.load(); },
  openComposer() { this.setData({ showComposer: true }); },
  closeComposer() { if (!this.data.publishing) this.setData({ showComposer: false }); },
  draftInput(e) { this.setData({ draft: e.detail.value }); },
  chooseImages() { wx.chooseMedia({ count: 9 - this.data.draftImages.length, mediaType: ['image'], sourceType: ['album', 'camera'], success: ({ tempFiles }) => this.setData({ draftImages: this.data.draftImages.concat(tempFiles).slice(0, 9) }) }); },
  removeImage(e) { const images = this.data.draftImages.slice(); images.splice(Number(e.currentTarget.dataset.index), 1); this.setData({ draftImages: images }); },
  previewImage(e) { wx.previewImage({ current: e.currentTarget.dataset.current, urls: e.currentTarget.dataset.urls }); },
  async publish() { if (this.data.publishing) return; const caption = this.data.draft.trim(); if (!caption && !this.data.draftImages.length) return wx.showToast({ title: '写点内容或选择照片', icon: 'none' }); this.setData({ publishing: true }); try { const imageUrls = []; for (const image of this.data.draftImages) imageUrls.push((await upload(image.tempFilePath)).url); await request('/sends/moments', { method: 'POST', data: { caption, imageUrls, visibility: 'public' } }); this.setData({ publishing: false, showComposer: false, draft: '', draftImages: [] }); wx.showToast({ title: '已发表', icon: 'success' }); this.load(); } catch (error) { this.setData({ publishing: false }); wx.showToast({ title: error.message || '发表失败', icon: 'none' }); } },
  preview(e) { wx.navigateTo({ url: `/pages/route/index?id=${e.currentTarget.dataset.id}` }); },
  openPost(e) { wx.navigateTo({ url: `/pages/post/index?id=${e.currentTarget.dataset.id}` }); },
  onShareAppMessage() { return { title: '完攀日记广场', path: '/pages/feed/index' }; }
});
