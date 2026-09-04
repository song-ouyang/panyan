import Fastify from "fastify";
import sensible from "@fastify/sensible";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ZodError } from "zod";

const mocks = vi.hoisted(() => ({ query: vi.fn() }));

vi.mock("../src/db.js", () => ({ query: mocks.query }));

import { gymRoutes } from "../src/routes/gyms.js";

const brandId = "00000000-0000-4000-8000-000000000101";
const gymId = "00000000-0000-4000-8000-000000000102";

function result(rows: unknown[] = []) {
  return { rows, rowCount: rows.length };
}

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({ code: "VALIDATION_ERROR" });
    }
    return reply.send(error);
  });
  await app.register(gymRoutes, { prefix: "/api/gyms" });
  return app;
}

beforeEach(() => mocks.query.mockReset());

describe("gym directory contract", () => {
  it("returns a stable brand summary and searches brand, store, address and district", async () => {
    const item = {
      city: "深圳",
      cities: ["深圳"],
      brand_id: brandId,
      brand_name: "香蕉攀岩",
      logo_url: null,
      store_count: 3,
      route_count: 19,
      verified: true,
    };
    mocks.query.mockResolvedValue(result([item]));
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/gyms/directory?city=%E6%B7%B1%E5%9C%B3&q=%E5%8D%97%E5%B1%B1",
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ items: [item] });
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain("WITH matched_brands");
    expect(sql).toContain("array_agg(DISTINCT g.city ORDER BY g.city) cities");
    expect(sql).toContain("coalesce(b.name,g.name) ILIKE");
    expect(sql).toContain("g.name ILIKE");
    expect(sql).toContain("g.address ILIKE");
    expect(sql).toContain("coalesce(g.district,'') ILIKE");
    expect(sql).toContain("count(DISTINCT g.id)::int store_count");
    expect(values).toEqual(["深圳", "南山"]);
    await app.close();
  });

  it("groups a nationwide directory once per brand and exposes its cities", async () => {
    const item = {
      city: null,
      cities: ["上海", "深圳"],
      brand_id: brandId,
      brand_name: "香蕉攀岩",
      logo_url: null,
      store_count: 5,
      route_count: 27,
      verified: true,
    };
    mocks.query.mockResolvedValue(result([item]));
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/gyms/directory",
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ items: [item] });
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain(
      "CASE WHEN $1::text IS NULL THEN NULL ELSE min(g.city) END city",
    );
    expect(sql).toContain(
      "GROUP BY coalesce(b.id,g.id),coalesce(b.name,g.name),b.logo_url",
    );
    expect(sql).not.toContain("GROUP BY g.city");
    expect(values).toEqual([null, null]);
    await app.close();
  });

  it("expands one brand into stores from the same city as its directory count", async () => {
    const brand = { id: brandId, name: "香蕉攀岩", logo_url: null };
    const stores = [
      {
        id: gymId,
        name: "香蕉攀岩·南山店",
        brand_id: brandId,
        district: "南山区",
        route_count: 19,
      },
      {
        id: "00000000-0000-4000-8000-000000000103",
        name: "香蕉攀岩·宝安店",
        brand_id: brandId,
        district: "宝安区",
        route_count: 8,
      },
    ];
    mocks.query
      .mockResolvedValueOnce(
        result([
          {
            city: "深圳",
            cities: ["深圳"],
            brand_id: brandId,
            brand_name: brand.name,
            store_count: stores.length,
          },
        ]),
      )
      .mockResolvedValueOnce(result([brand]))
      .mockResolvedValueOnce(result(stores));
    const app = await createApp();

    const directoryResponse = await app.inject({
      method: "GET",
      url: "/api/gyms/directory?city=%E6%B7%B1%E5%9C%B3",
    });
    const response = await app.inject({
      method: "GET",
      url: `/api/gyms/brands/${brandId}/stores?city=%E6%B7%B1%E5%9C%B3`,
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ...brand, stores });
    expect(mocks.query.mock.calls[2]![0]).toContain("WHERE g.brand_id=$1");
    expect(mocks.query.mock.calls[2]![0]).toContain("g.city=$2");
    expect(mocks.query.mock.calls[2]![0]).toContain(
      "ORDER BY g.city,g.district,g.name",
    );
    expect(mocks.query.mock.calls[2]![1]).toEqual([brandId, "深圳"]);
    expect(response.json().stores).toHaveLength(
      directoryResponse.json().items[0].store_count,
    );
    await app.close();
  });

  it("keeps direct brand expansion global when city is omitted", async () => {
    mocks.query
      .mockResolvedValueOnce(result([{ id: brandId, name: "香蕉攀岩" }]))
      .mockResolvedValueOnce(result([]));
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: `/api/gyms/brands/${brandId}/stores`,
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[1]![1]).toEqual([brandId, null]);
    await app.close();
  });

  it("normalizes empty city and q values to omitted filters", async () => {
    mocks.query.mockResolvedValue(result([]));
    const app = await createApp();

    const directory = await app.inject({
      method: "GET",
      url: "/api/gyms/directory?city=&q=",
    });
    const flat = await app.inject({
      method: "GET",
      url: "/api/gyms?city=%20%20&q=%20",
    });

    expect(directory.statusCode).toBe(200);
    expect(flat.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([null, null]);
    expect(mocks.query.mock.calls[1]![1]).toEqual([null, null]);
    await app.close();
  });

  it("returns brand_name on every flat gym row and uses the same search surface", async () => {
    const store = {
      id: gymId,
      name: "香蕉攀岩·南山店",
      brand_id: brandId,
      brand_name: "香蕉攀岩",
      city: "深圳",
      district: "南山区",
      address: "南山区示例路1号",
      route_count: 19,
    };
    mocks.query.mockResolvedValue(result([store]));
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/gyms?q=%E7%A4%BA%E4%BE%8B%E8%B7%AF",
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().items[0]).toMatchObject({
      id: gymId,
      brand_name: "香蕉攀岩",
    });
    const [sql, values] = mocks.query.mock.calls[0]!;
    expect(sql).toContain("LEFT JOIN gym_brands b");
    expect(sql).toContain("coalesce(b.name,g.name) brand_name");
    expect(sql).toContain("g.address ILIKE");
    expect(sql).toContain("coalesce(g.district,'') ILIKE");
    expect(values).toEqual([null, "示例路"]);
    await app.close();
  });
});
