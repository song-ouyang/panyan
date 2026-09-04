import Fastify from "fastify";
import sensible from "@fastify/sensible";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ZodError } from "zod";

const mocks = vi.hoisted(() => ({ query: vi.fn() }));

vi.mock("../src/db.js", () => ({ query: mocks.query }));

import { rankingRoutes } from "../src/routes/rankings.js";

function result(rows: unknown[] = []) {
  return { rows, rowCount: rows.length };
}

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  app.decorate("authenticateOptional", async () => undefined);
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({ code: "VALIDATION_ERROR" });
    }
    return reply.send(error);
  });
  await app.register(rankingRoutes, { prefix: "/api/rankings" });
  return app;
}

beforeEach(() => {
  mocks.query.mockReset();
  mocks.query.mockResolvedValue(result([]));
});

describe("ranking query validation", () => {
  it.each([
    "/api/rankings/routes?gymId=not-a-uuid",
    "/api/rankings/routes?setId=also-not-a-uuid",
    "/api/rankings/routes?province=%E5%9B%9B%E5%B7%9D%E7%9C%81",
    "/api/rankings/routes?city=%E6%88%90%E9%83%BD",
    "/api/rankings?scope=unknown",
    "/api/rankings?scope=national&city=%E6%B7%B1%E5%9C%B3",
    "/api/rankings?scope=province",
    "/api/rankings?scope=province&province=%E5%B9%BF%E4%B8%9C%E7%9C%81&city=%E6%B7%B1%E5%9C%B3",
    "/api/rankings?scope=city&city=%E6%B7%B1%E5%9C%B3",
  ])("returns 400 before SQL for invalid combinations: %s", async (url) => {
    const app = await createApp();

    const response = await app.inject({ method: "GET", url });

    expect(response.statusCode).toBe(400);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it("accepts empty optional ids as omitted values", async () => {
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/rankings/routes?gymId=&setId=",
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([
      null,
      null,
      null,
      null,
      null,
    ]);
    expect(mocks.query.mock.calls[0]![0]).toContain("blocked.status='blocked'");
    await app.close();
  });

  it("passes a complete city route filter to SQL", async () => {
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/rankings/routes?province=%E5%9B%9B%E5%B7%9D%E7%9C%81&city=%E6%88%90%E9%83%BD",
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([
      null,
      null,
      "四川省",
      "成都",
      null,
    ]);
    expect(mocks.query.mock.calls[0]![0]).toContain(
      "g.province=$3 AND g.city=$4",
    );
    expect(mocks.query.mock.calls[0]![0]).toContain(
      "substring(r.grade from 2)::int DESC,r.id",
    );
    await app.close();
  });

  it("passes only a complete city scope to SQL", async () => {
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/rankings?scope=city&province=%E5%B9%BF%E4%B8%9C%E7%9C%81&city=%E6%B7%B1%E5%9C%B3",
    });

    expect(response.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![1]).toEqual([
      null,
      null,
      "city",
      "广东省",
      "深圳",
      null,
    ]);
    expect(mocks.query.mock.calls[0]![0]).toContain("blocked.status='blocked'");
    await app.close();
  });
});
