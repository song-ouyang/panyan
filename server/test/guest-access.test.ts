import Fastify from "fastify";
import sensible from "@fastify/sensible";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  config: {
    JWT_SECRET: "guest-access-test-secret-at-least-32-characters",
    MODERATION_MODE: "off",
  },
}));

vi.mock("../src/db.js", () => ({ query: mocks.query }));
vi.mock("../src/config.js", () => ({ config: mocks.config }));

import { authPlugin } from "../src/auth.js";
import { rankingRoutes } from "../src/routes/rankings.js";
import { sendRoutes } from "../src/routes/sends.js";

const viewerId = "00000000-0000-4000-8000-000000000201";
const sendId = "00000000-0000-4000-8000-000000000202";

function result(rows: unknown[] = []) {
  return { rows, rowCount: rows.length };
}

async function createApp() {
  const app = Fastify();
  await app.register(sensible);
  await app.register(authPlugin);
  await app.register(sendRoutes, { prefix: "/api/sends" });
  await app.register(rankingRoutes, { prefix: "/api/rankings" });
  return app;
}

beforeEach(() => mocks.query.mockReset());

describe("real optional JWT behavior", () => {
  it("lets a guest discover ranking regions", async () => {
    mocks.query.mockResolvedValue(
      result([{ province: "四川省", city: "成都" }]),
    );
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/rankings/regions",
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().items).toEqual([
      { province: "四川省", city: "成都" },
    ]);
    await app.close();
  });

  it("does not downgrade an invalid session on a public city route ranking", async () => {
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/rankings/routes?province=%E5%9B%9B%E5%B7%9D%E7%9C%81&city=%E6%88%90%E9%83%BD",
      headers: { authorization: "Bearer definitely-invalid" },
    });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it("allows a request without Authorization to browse the public square", async () => {
    mocks.query.mockResolvedValue(
      result([
        {
          id: sendId,
          visibility: "public",
          liked: false,
          sent_at: "2026-09-04T00:00:00Z",
        },
      ]),
    );
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/sends/feed?scope=square",
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().items[0]).toMatchObject({
      id: sendId,
      visibility: "public",
      liked: false,
    });
    expect(mocks.query.mock.calls[0]![1]).toEqual([
      null,
      null,
      null,
      20,
      "square",
    ]);
    await app.close();
  });

  it("does not silently downgrade a malformed JWT to guest access", async () => {
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: "/api/sends/feed?scope=square",
      headers: { authorization: "Bearer definitely-invalid" },
    });

    expect(response.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();
    await app.close();
  });

  it.each(["", "   ", "Basic not-a-bearer-token"])(
    "rejects a present but unusable Authorization header (%j)",
    async (authorization) => {
      const app = await createApp();

      const response = await app.inject({
        method: "GET",
        url: "/api/sends/feed?scope=square",
        headers: { authorization },
      });

      expect(response.statusCode).toBe(401);
      expect(mocks.query).not.toHaveBeenCalled();
      await app.close();
    },
  );

  it("keeps the friends feed login-gated but accepts a valid session", async () => {
    mocks.query
      .mockResolvedValueOnce(result([{ id: viewerId, role: "user" }]))
      .mockResolvedValueOnce(result());
    const app = await createApp();

    const guestResponse = await app.inject({
      method: "GET",
      url: "/api/sends/feed?scope=friends",
    });
    expect(guestResponse.statusCode).toBe(401);
    expect(mocks.query).not.toHaveBeenCalled();

    const token = app.jwt.sign({ sub: viewerId, role: "user" });
    const memberResponse = await app.inject({
      method: "GET",
      url: "/api/sends/feed?scope=friends",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(memberResponse.statusCode).toBe(200);
    expect(mocks.query.mock.calls[0]![0]).toContain("SELECT id,role FROM users");
    expect(mocks.query.mock.calls[0]![1]).toEqual([viewerId]);
    expect(mocks.query.mock.calls[1]![1]).toEqual([
      viewerId,
      null,
      null,
      20,
      "friends",
    ]);
    await app.close();
  });

  it("allows a guest to read an approved public post detail and comments", async () => {
    const post = {
      id: sendId,
      visibility: "public",
      moderation_status: "approved",
      liked: false,
    };
    const comment = {
      id: "00000000-0000-4000-8000-000000000203",
      content: "很棒",
    };
    mocks.query
      .mockResolvedValueOnce(result([post]))
      .mockResolvedValueOnce(result([comment]));
    const app = await createApp();

    const response = await app.inject({
      method: "GET",
      url: `/api/sends/${sendId}`,
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ...post, comments: [comment] });
    expect(mocks.query.mock.calls[0]![1]).toEqual([sendId, null]);
    expect(mocks.query.mock.calls[1]![1]).toEqual([sendId, null]);
    await app.close();
  });
});
