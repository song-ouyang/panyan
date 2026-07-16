const { request } = require('../../utils/api');
Page({ data: { items: [] }, onShow() { this.load(); }, async load() { const data = await request('/submissions/mine'); this.setData({ items: data.items }); } });
