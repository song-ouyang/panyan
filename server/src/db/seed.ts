import { pool } from '../db.js';

const gym = await pool.query<{ id: string }>(
  `INSERT INTO gyms(name,province,city,address,description,verified)
   VALUES('测试抱石馆','广东省','深圳','南山区示例路1号','用于本地开发的示例岩馆',true)
   RETURNING id`
);
const gymId = gym.rows[0]!.id;
const set = await pool.query<{ id: string }>(
  `INSERT INTO route_sets(gym_id,name,starts_on,ends_on) VALUES($1,'七月线路',current_date,current_date+interval '30 days') RETURNING id`, [gymId]
);
const colors = ['珊瑚橙', '湖蓝', '紫色', '黄色'];
for (let grade = 0; grade <= 5; grade += 1) {
  for (let i = 1; i <= 3; i += 1) {
    await pool.query(
      `INSERT INTO routes(gym_id,route_set_id,name,grade,color,wall_zone) VALUES($1,$2,$3,$4,$5,$6)`,
      [gymId, set.rows[0]!.id, `V${grade}-${i}`, `V${grade}`, colors[(grade + i) % colors.length], `${String.fromCharCode(65 + grade)}区`]
    );
  }
}
await pool.end();
console.log('Seed complete');
