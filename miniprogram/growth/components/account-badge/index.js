const atlas = require('../../assets/account-levels');
Component({
  properties: { level: { type: Number, value: 0 }, size: { type: Number, value: 200 }, muted: { type: Boolean, value: false } },
  data: { imageStyle: '', found: false },
  observers: {
    'level, size': function(level, size) {
      const rect = atlas.badges.find(item => item.level === Number(level));
      if (!rect) return this.setData({ found: false });
      const scale = Math.max(1, Number(size) || 200) / rect.width;
      this.setData({ found: true, imageStyle: `width:${atlas.width * scale}rpx;height:${atlas.height * scale}rpx;left:${-rect.x * scale}rpx;top:${-rect.y * scale}rpx;` });
    }
  },
  methods: { imageReady() { this.triggerEvent('ready'); } }
});
