// Helpdesk Hero API — Bunny Edge Script (standalone) backed by Bunny Database.
// Env (set automatically when the database is linked to the script):
//   BUNNY_DATABASE_URL, BUNNY_DATABASE_AUTH_TOKEN
// Optional env: ALLOWED_ORIGIN (default "*")
import * as BunnySDK from "npm:@bunny.net/edgescript-sdk@0.12.1";
import { connect } from "npm:@bunny.net/database-client";

const env = (k: string): string | undefined =>
  (globalThis as any).Deno?.env?.get?.(k) ?? (globalThis as any).process?.env?.[k];

const db = connect({ timeout: 10000 });  // idle databases take a few seconds to wake
const ORIGIN = env("ALLOWED_ORIGIN") ?? "*";
const SESSION_DAYS = 30;
const PBKDF2_ITER = 100_000;

// ---------- schema (idempotent, runs once per isolate) ----------
let schemaReady: Promise<unknown> | null = null;
function ensureSchema() {
  schemaReady ??= db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE COLLATE NOCASE,
      pass_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      created_at INTEGER NOT NULL)`),
    db.prepare(`CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL)`),
    db.prepare(`CREATE TABLE IF NOT EXISTS saves (
      user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      coins INTEGER NOT NULL DEFAULT 0,
      data TEXT NOT NULL DEFAULT '{}',
      updated_at INTEGER NOT NULL)`),
    db.prepare(`CREATE INDEX IF NOT EXISTS saves_coins ON saves(coins DESC)`),
  ]).catch((e) => { schemaReady = null; throw e; });
  return schemaReady;
}

// ---------- helpers ----------
const now = () => Math.floor(Date.now() / 1000);
const hex = (b: ArrayBuffer | Uint8Array) =>
  [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const randomHex = (n: number) => hex(crypto.getRandomValues(new Uint8Array(n)));
const sha256 = async (s: string) => hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));

async function hashPassword(password: string, saltHex: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const salt = new Uint8Array(saltHex.match(/../g)!.map((h) => parseInt(h, 16)));
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: PBKDF2_ITER }, key, 256);
  return hex(bits);
}

function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

const cors = {
  "Access-Control-Allow-Origin": ORIGIN,
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (error: string, status = 400) => json({ error }, status);

async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const text = await req.text();
    if (text.length > 8192) return {};
    const v = JSON.parse(text);
    return v && typeof v === "object" ? v : {};
  } catch { return {}; }
}

async function createSession(userId: number) {
  const token = randomHex(32);
  await db.prepare("INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)")
    .bind(await sha256(token), userId, now() + SESSION_DAYS * 86400).run();
  return token;
}

// Token comes from the Authorization header, or from the body for sendBeacon saves on tab close
// (beacons can't set headers, and a text/plain body avoids a CORS preflight).
async function authUser(req: Request, bodyToken = ""): Promise<{ id: number; username: string } | null> {
  const header = (req.headers.get("Authorization") ?? "").match(/^Bearer ([0-9a-f]{64})$/)?.[1];
  const tok = header ?? (/^[0-9a-f]{64}$/.test(bodyToken) ? bodyToken : null);
  if (!tok) return null;
  return await db.prepare(
    `SELECT u.id, u.username FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at > ?`,
  ).bind(await sha256(tok), now()).first();
}

async function loadSave(userId: number) {
  const row = await db.prepare("SELECT coins, data FROM saves WHERE user_id = ?").bind(userId).first<{ coins: number; data: string }>();
  if (!row) return { coins: 0 };
  let extra: Record<string, unknown> = {};
  try { extra = JSON.parse(row.data); } catch { /* ignore */ }
  return { ...extra, coins: row.coins };
}

// Whitelist of save fields. Daily changes add fields here.
// coins = career cash earned (A$); it's what the leaderboard ranks.
const int = (v: unknown, max = 1_000_000_000) => Math.max(0, Math.min(max, Math.floor(Number(v) || 0)));
function cleanSave(b: Record<string, unknown>) {
  return {
    coins: int(b.coins),
    data: {
      playtime: int(b.playtime),
      seq: int(b.seq),
      shifts: int(b.shifts, 1_000_000),
      solved: int(b.solved, 10_000_000),
      best: int(b.best),
    },
  };
}

// ---------- routes ----------
const USER_RE = /^[A-Za-z0-9_]{3,20}$/;

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  try {
    await ensureSchema();
  } catch {
    await ensureSchema();  // one retry covers a cold-start timeout
  }

  if (req.method === "GET" && path === "/api/health") return json({ ok: true });
  const body = req.method === "POST" ? await readJson(req) : {};

  if (req.method === "POST" && (path === "/api/register" || path === "/api/login")) {
    const username = String(body.username ?? "");
    const password = String(body.password ?? "");
    if (!USER_RE.test(username)) return fail("Username: 3-20 letters, numbers or _");
    if (password.length < 8 || password.length > 200) return fail("Password must be 8+ characters");

    let userId: number;
    if (path === "/api/register") {
      const salt = randomHex(16);
      try {
        const r = await db.prepare("INSERT INTO users (username, pass_hash, salt, created_at) VALUES (?, ?, ?, ?) RETURNING id")
          .bind(username, await hashPassword(password, salt), salt, now()).run();
        userId = Number((r.rows[0] as { id: number }).id);
      } catch (e: any) {
        if (String(e?.code ?? e?.message).includes("CONSTRAINT")) return fail("Username taken", 409);
        throw e;
      }
    } else {
      const u = await db.prepare("SELECT id, pass_hash, salt FROM users WHERE username = ?").bind(username)
        .first<{ id: number; pass_hash: string; salt: string }>();
      if (!u || !safeEqual(await hashPassword(password, u.salt), u.pass_hash)) return fail("Wrong username or password", 401);
      userId = u.id;
    }
    const token = await createSession(userId);
    return json({ token, username, save: await loadSave(userId) });
  }

  if (req.method === "GET" && path === "/api/leaderboard") {
    const rows = await db.prepare(
      "SELECT u.username, s.coins FROM saves s JOIN users u ON u.id = s.user_id WHERE u.username NOT LIKE 'smoke\\_%' ESCAPE '\\' ORDER BY s.coins DESC LIMIT 10",
    ).all();
    return json({ rows });
  }

  const user = await authUser(req, String(body.token ?? ""));
  if (!user) return fail("Not logged in", 401);

  if (req.method === "GET" && path === "/api/me") return json({ username: user.username, save: await loadSave(user.id) });

  if (req.method === "POST" && path === "/api/save") {
    const s = cleanSave(body);
    // Reads may come from a lagging replica, so never read-after-write here; the client keeps
    // its own copy with a sequence number and reconciles on load (see main.gd _on_logged_in).
    // Ignore out-of-order saves (e.g. a slow request landing after a newer beacon).
    const w = await db.prepare(
      `INSERT INTO saves (user_id, coins, data, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET coins = excluded.coins, data = excluded.data, updated_at = excluded.updated_at
       WHERE COALESCE(json_extract(saves.data, '$.seq'), 0) <= COALESCE(json_extract(excluded.data, '$.seq'), 0)
       RETURNING coins`,
    ).bind(user.id, s.coins, JSON.stringify(s.data), now()).run();
    return json({ ok: true, written: w.rowsAffected > 0, coins: s.coins });
  }

  if (req.method === "POST" && path === "/api/logout") {
    const m = (req.headers.get("Authorization") ?? "").match(/^Bearer ([0-9a-f]{64})$/);
    if (m) await db.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(m[1])).run();
    return json({ ok: true });
  }

  return fail("Not found", 404);
}

BunnySDK.net.http.serve(async (req: Request) => {
  try {
    return await handle(req);
  } catch (e) {
    console.error(e);
    return fail("Server error", 500);
  }
});
