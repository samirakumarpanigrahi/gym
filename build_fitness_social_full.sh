#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)/fitness_social_full_project"
ZIP_NAME="fitness_social_full_release.zip"

echo "Creating project in $ROOT"
rm -rf "$ROOT"
mkdir -p "$ROOT/backend" "$ROOT/frontend" "$ROOT/backend/migrations" "$ROOT/backend/seeds" "$ROOT/frontend/screens" "$ROOT/frontend/services" "$ROOT/frontend/components" "$ROOT/.github/workflows"

# -----------------------
# BACKEND: package.json
# -----------------------
cat > "$ROOT/backend/package.json" <<'JSON'
{
  "name": "fitness-social-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3",
    "express": "^4.18.2",
    "multer": "^1.4.5",
    "pg": "^8.11.0",
    "uuid": "^9.0.0",
    "jsonwebtoken": "^9.0.0"
  }
}
JSON

# -----------------------
# BACKEND: server_auth_helpers/auth.js
# -----------------------
mkdir -p "$ROOT/backend/server_auth_helpers"
cat > "$ROOT/backend/server_auth_helpers/auth.js" <<'JS'
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');

const JWT_SECRET = process.env.JWT_SECRET || 'change_this';
const SALT_ROUNDS = 10;

async function hashPassword(password) {
  return bcrypt.hash(password, SALT_ROUNDS);
}

async function comparePassword(password, hash) {
  return bcrypt.compare(password, hash);
}

function generateAccessToken(payload, opts={}) {
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: opts.expiresIn || '1h' });
  return token;
}

function verifyJwt(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (e) {
    return null;
  }
}

function generateRefreshToken() {
  return uuidv4();
}

module.exports = { hashPassword, comparePassword, generateAccessToken, verifyJwt, generateRefreshToken };
JS

# -----------------------
# BACKEND: middleware/requireAuth.js
# (simple middleware to extract user from DB via JWT)
# -----------------------
mkdir -p "$ROOT/backend/middleware"
cat > "$ROOT/backend/middleware/requireAuth.js" <<'JS'
module.exports = function requireAuth(pool) {
  return async function (req, res, next) {
    const authHeader = req.headers.authorization || '';
    if (!authHeader) return res.status(401).json({ error: 'no_auth' });
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;
    const auth = require('../server_auth_helpers/auth');
    const payload = auth.verifyJwt(token);
    if (!payload || !payload.userId) return res.status(401).json({ error: 'invalid_token' });
    try {
      const client = await pool.connect();
      const r = await client.query('SELECT id, username, display_name, email, avatar_url, gym_id FROM users WHERE id = $1 LIMIT 1', [payload.userId]);
      client.release();
      if (r.rowCount === 0) return res.status(401).json({ error: 'user_not_found' });
      req.user = r.rows[0];
      next();
    } catch (e) {
      console.error('requireAuth error', e);
      res.status(500).json({ error: 'auth_failed' });
    }
  }
}
JS

# -----------------------
# BACKEND: migrations 001_create_schema.sql (abbreviated)
# -----------------------
cat > "$ROOT/backend/migrations/001_create_schema.sql" <<'SQL'
-- Minimal schema for users, posts, workouts, workouts_exercises, sets, posts
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username TEXT UNIQUE,
  display_name TEXT,
  email TEXT UNIQUE,
  password_hash TEXT,
  avatar_url TEXT,
  gym_id UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workouts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT,
  date TIMESTAMP WITH TIME ZONE,
  privacy TEXT DEFAULT 'private',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workout_exercises (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_id UUID REFERENCES workouts(id) ON DELETE CASCADE,
  exercise_name TEXT,
  primary_muscle TEXT,
  "order" INT
);

CREATE TABLE IF NOT EXISTS sets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_exercise_id UUID REFERENCES workout_exercises(id) ON DELETE CASCADE,
  set_no INT,
  reps INT,
  weight NUMERIC,
  rpe NUMERIC,
  rest_seconds INT
);

CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type TEXT,
  linked_workout_id UUID REFERENCES workouts(id),
  caption TEXT,
  visibility_status TEXT DEFAULT 'visible',
  likes_count INT DEFAULT 0,
  comments_count INT DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- gyms table for B1
CREATE TABLE IF NOT EXISTS gyms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  address TEXT,
  lat NUMERIC,
  lon NUMERIC,
  photo_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
SQL

# -----------------------
# BACKEND: migrations 002_refresh_tokens.sql
# -----------------------
cat > "$ROOT/backend/migrations/002_refresh_tokens.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS refresh_tokens (
  token TEXT PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
SQL

# -----------------------
# BACKEND: migrations 003_social.sql (likes/comments/follows/notifications)
# -----------------------
cat > "$ROOT/backend/migrations/003_social.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS follows (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  follower_id UUID REFERENCES users(id) ON DELETE CASCADE,
  followee_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE (follower_id, followee_id)
);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  verb TEXT,
  target_type TEXT,
  target_id UUID,
  data JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
SQL

# -----------------------
# BACKEND: migrations 004_challenges.sql (B2)
# -----------------------
cat > "$ROOT/backend/migrations/004_challenges.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS challenges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  creator_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  gym_id UUID REFERENCES gyms(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  start_date TIMESTAMP WITH TIME ZONE NOT NULL,
  end_date TIMESTAMP WITH TIME ZONE NOT NULL,
  goal_type TEXT NOT NULL,
  goal_value NUMERIC NOT NULL DEFAULT 0,
  visibility TEXT DEFAULT 'public',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS challenge_participants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenge_id UUID REFERENCES challenges(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  progress_value NUMERIC DEFAULT 0,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE (challenge_id, user_id)
);
SQL

# -----------------------
# BACKEND: seeds/001_seed_demo.sql
# -----------------------
cat > "$ROOT/backend/seeds/001_seed_demo.sql" <<'SQL'
-- create a demo user
INSERT INTO users (id, username, display_name, email, password_hash)
VALUES ('22222222-2222-2222-2222-222222222222','demo_user','Demo User','demo@example.com','$2a$10$KbQiYgZDlqgWZ6xQ1Yq3eOKnQpI1bQmWf1cQk1y6') ON CONFLICT DO NOTHING;

-- demo post/workout placeholder (IDs used by seeds)
INSERT INTO workouts (id, user_id, title, date) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','Demo Workout', now()) ON CONFLICT DO NOTHING;
INSERT INTO posts (id, author_id, type, linked_workout_id, caption, visibility_status) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','workout','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Demo workout post','visible') ON CONFLICT DO NOTHING;

-- sample gyms
INSERT INTO gyms (id, name, lat, lon, address, photo_url)
VALUES
('g1aaaaaaaa-1111-1111-1111-111111111111','Iron Temple Gym',28.6139,77.2090,'Connaught Place, New Delhi, India',NULL)
ON CONFLICT DO NOTHING;
INSERT INTO gyms (id, name, lat, lon, address, photo_url)
VALUES
('g2bbbbbbbb-2222-2222-2222-222222222222','Steel City Fitness',28.7041,77.1025,'Delhi NCR',NULL)
ON CONFLICT DO NOTHING;
INSERT INTO gyms (id, name, lat, lon, address, photo_url)
VALUES
('g3cccccccc-3333-3333-3333-333333333333','Mumbai Muscle Club',19.0760,72.8777,'Mumbai',NULL)
ON CONFLICT DO NOTHING;

-- sample challenge
INSERT INTO challenges (id, creator_user_id, gym_id, title, description, start_date, end_date, goal_type, goal_value, visibility)
VALUES ('sample_challenge_1','22222222-2222-2222-2222-222222222222','g1aaaaaaaa-1111-1111-1111-111111111111',
 '7-day Push Challenge','Do at least 1 logged workout per day for 7 days', now(), now() + interval '7 days', 'workouts_count', 7, 'gym')
ON CONFLICT DO NOTHING;
SQL

# -----------------------
# BACKEND: server.js (long single-file Express server)
# -----------------------
cat > "$ROOT/backend/server.js" <<'JS'
require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { Pool } = require('pg');
const { v4: uuidv4 } = require('uuid');
const auth = require('./server_auth_helpers/auth');
const requireAuth = require('./middleware/requireAuth');

const pool = new Pool({ connectionString: process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/fitness_social' });

const app = express();
app.use(cors());
app.use(bodyParser.json());

// Serve uploaded files
const multer = require('multer');
const path = require('path');
const PUBLIC_DIR = path.join(__dirname, 'public');
if (!require('fs').existsSync(path.join(PUBLIC_DIR,'uploads'))) require('fs').mkdirSync(path.join(PUBLIC_DIR,'uploads'), { recursive: true });
app.use('/uploads', express.static(path.join(PUBLIC_DIR,'uploads')));

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, path.join(PUBLIC_DIR,'uploads'))
  },
  filename: function (req, file, cb) {
    const unique = Date.now() + '-' + Math.round(Math.random()*1E9);
    cb(null, unique + '-' + file.originalname.replace(/[^a-zA-Z0-9.\-_]/g,'_'))
  }
});
const upload = multer({ storage: storage });

// Auth routes
app.post('/api/auth/register', async (req, res) => {
  const { username, email, password, display_name } = req.body;
  if (!username || !email || !password) return res.status(400).json({error: 'username,email,password required'});
  const client = await pool.connect();
  try {
    const hashed = await auth.hashPassword(password);
    const id = uuidv4();
    await client.query(
      `INSERT INTO users (id, username, display_name, email, password_hash, created_at)
       VALUES ($1,$2,$3,$4,$5, now())`,
       [id, username, display_name || username, email, hashed]
    );
    const accessToken = auth.generateAccessToken({ userId: id });
    const refreshToken = auth.generateRefreshToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
    await client.query(`INSERT INTO refresh_tokens (token, user_id, expires_at) VALUES ($1,$2,$3)`, [refreshToken, id, expiresAt]);
    res.json({ token: accessToken, refreshToken, user: { id, username, display_name: display_name || username, email } });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'registration_failed' });
  } finally {
    client.release();
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { username, email, password } = req.body;
  if ((!username && !email) || !password) return res.status(400).json({error: 'username/email and password required'});
  const client = await pool.connect();
  try {
    const q = username ? 'username' : 'email';
    const v = username || email;
    const r = await client.query(`SELECT id, username, display_name, email, password_hash FROM users WHERE ${q} = $1 LIMIT 1`, [v]);
    if (r.rowCount === 0) return res.status(401).json({ error: 'invalid_credentials' });
    const user = r.rows[0];
    const ok = await auth.comparePassword(password, user.password_hash);
    if (!ok) return res.status(401).json({ error: 'invalid_credentials' });
    const accessToken = auth.generateAccessToken({ userId: user.id });
    const refreshToken = auth.generateRefreshToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30);
    await client.query(`INSERT INTO refresh_tokens (token, user_id, expires_at) VALUES ($1,$2,$3)`, [refreshToken, user.id, expiresAt]);
    delete user.password_hash;
    const userOut = { id: user.id, username: user.username, display_name: user.display_name, email: user.email };
    res.json({ token: accessToken, refreshToken, user: userOut });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'login_failed' });
  } finally {
    client.release();
  }
});

// Refresh endpoint
app.post('/api/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(400).json({ error: 'refresh_token_required' });
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT token, user_id, expires_at FROM refresh_tokens WHERE token = $1 LIMIT 1`, [refreshToken]);
    if (r.rowCount === 0) return res.status(401).json({ error: 'invalid_refresh' });
    const row = r.rows[0];
    const expiresAt = new Date(row.expires_at);
    if (expiresAt < new Date()) {
      await client.query(`DELETE FROM refresh_tokens WHERE token = $1`, [refreshToken]);
      return res.status(401).json({ error: 'refresh_expired' });
    }
    const newAccess = auth.generateAccessToken({ userId: row.user_id });
    res.json({ token: newAccess });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'refresh_failed' });
  } finally {
    client.release();
  }
});

// Logout
app.post('/api/auth/logout', requireAuth(pool), async (req, res) => {
  const { refreshToken } = req.body;
  const client = await pool.connect();
  try {
    if (refreshToken) {
      await client.query(`DELETE FROM refresh_tokens WHERE token = $1`, [refreshToken]);
    }
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'logout_failed' });
  } finally {
    client.release();
  }
});

// Upload endpoint for avatars/media
app.post('/api/upload', requireAuth(pool), upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'no_file' });
    const url = `${req.protocol}://${req.get('host')}/uploads/${req.file.filename}`;
    res.json({ url });
  } catch (e) { console.error(e); res.status(500).json({ error: 'upload_failed' }); }
});

// Get current user
app.get('/api/user/me', requireAuth(pool), async (req, res) => {
  res.json(req.user);
});

// Update profile
app.put('/api/user/me', requireAuth(pool), async (req, res) => {
  const { display_name, avatar_url } = req.body;
  const client = await pool.connect();
  try {
    await client.query(`UPDATE users SET display_name = COALESCE($1, display_name), avatar_url = COALESCE($2, avatar_url) WHERE id = $3`, [display_name, avatar_url, req.user.id]);
    const r = await client.query('SELECT id, username, display_name, email, avatar_url FROM users WHERE id = $1', [req.user.id]);
    res.json(r.rows[0]);
  } catch (e) { console.error(e); res.status(500).json({ error: 'update_failed' }); } finally { client.release(); }
});

// --- Gyms & local feed endpoints ---
app.get('/api/gyms/nearby', async (req, res) => {
  const { lat, lng } = req.query;
  const client = await pool.connect();
  try {
    if (!lat || !lng) {
      const r = await client.query('SELECT id, name, lat, lon, address, photo_url FROM gyms LIMIT 50');
      return res.json(r.rows);
    }
    const r = await client.query(
      `SELECT id, name, lat, lon, address, photo_url,
        ((lat::double precision - $1::double precision)*(lat::double precision - $1::double precision) + (lon::double precision - $2::double precision)*(lon::double precision - $2::double precision)) as dist2
       FROM gyms
       ORDER BY dist2 ASC
       LIMIT 50`, [parseFloat(lat), parseFloat(lng)]
    );
    res.json(r.rows.map(row => ({ id: row.id, name: row.name, lat: row.lat, lon: row.lon, address: row.address, photo_url: row.photo_url })));
  } catch (e) { console.error(e); res.status(500).json({ error: 'gyms_nearby_failed' }); } finally { client.release(); }
});

app.get('/api/gyms/:id', async (req, res) => {
  const id = req.params.id;
  const client = await pool.connect();
  try {
    const r = await client.query('SELECT id, name, lat, lon, address, photo_url FROM gyms WHERE id = $1 LIMIT 1', [id]);
    if (r.rowCount === 0) return res.status(404).json({ error: 'not_found' });
    res.json(r.rows[0]);
  } catch (e) { console.error(e); res.status(500).json({ error: 'gym_detail_failed' }); } finally { client.release(); }
});

app.get('/api/gyms/:id/members', async (req, res) => {
  const id = req.params.id;
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u WHERE u.gym_id = $1 LIMIT 100`, [id]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'gym_members_failed' }); } finally { client.release(); }
});

app.post('/api/gyms/:id/join', requireAuth(pool), async (req, res) => {
  const id = req.params.id;
  const userId = req.user.id;
  const client = await pool.connect();
  try {
    await client.query('UPDATE users SET gym_id = $1 WHERE id = $2', [id, userId]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'join_gym_failed' }); } finally { client.release(); }
});

// Public feed (supports ?scope=local)
app.get('/api/feed', async (req, res) => {
  const client = await pool.connect();
  try {
    const scope = req.query.scope || 'global';
    let r;
    if (scope === 'local' && req.headers && req.headers.authorization) {
      // try to obtain user's gym id from token (best-effort)
      let userGym = null;
      try {
        const authHeader = req.headers.authorization || '';
        const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;
        const payload = auth.verifyJwt(token);
        if (payload && payload.userId) {
          const ur = await client.query('SELECT gym_id FROM users WHERE id = $1', [payload.userId]);
          if (ur.rowCount>0) userGym = ur.rows[0].gym_id;
        }
      } catch(e) { /* ignore */ }
      if (userGym) {
        r = await client.query(`
          SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title
          FROM posts p
          JOIN users u ON u.id = p.author_id
          LEFT JOIN workouts w ON w.id = p.linked_workout_id
          WHERE p.visibility_status = 'visible' AND u.gym_id = $1
          ORDER BY p.created_at DESC
          LIMIT 50
        `, [userGym]);
      } else {
        r = await client.query(`
          SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title
          FROM posts p
          JOIN users u ON u.id = p.author_id
          LEFT JOIN workouts w ON w.id = p.linked_workout_id
          WHERE p.visibility_status = 'visible'
          ORDER BY p.created_at DESC
          LIMIT 50
        `);
      }
    } else {
      r = await client.query(`
          SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title
          FROM posts p
          JOIN users u ON u.id = p.author_id
          LEFT JOIN workouts w ON w.id = p.linked_workout_id
          WHERE p.visibility_status = 'visible'
          ORDER BY p.created_at DESC
          LIMIT 50
        `);
    }

    const posts = r.rows.map(row => ({
      id: row.id,
      caption: row.caption,
      createdAt: row.created_at,
      author: { id: row.author_id, username: row.username, displayName: row.display_name },
      workout: { id: row.workout_id, title: row.workout_title, exercises: [] }
    }));
    res.json(posts);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'feed_error' });
  } finally {
    client.release();
  }
});

// Create workout
app.post('/api/workouts', requireAuth(pool), async (req, res) => {
  const { title, exercises, date } = req.body;
  const userId = req.user.id;
  const client = await pool.connect();
  try {
    const workoutId = uuidv4();
    await client.query(
      `INSERT INTO workouts (id, user_id, title, date, privacy, created_at)
       VALUES ($1,$2,$3,$4,'private', now())`,
       [workoutId, userId, title || 'Workout', date || new Date()]
    );
    for (let i=0;i<(exercises||[]).length;i++){
      const ex = exercises[i];
      const exId = uuidv4();
      await client.query(
        `INSERT INTO workout_exercises (id, workout_id, exercise_name, primary_muscle, "order")
         VALUES ($1,$2,$3,$4,$5)`,
         [exId, workoutId, ex.exercise_name, ex.primary_muscle || null, i]
      );
      for (let j=0;j<(ex.sets||[]).length;j++){
        const s = ex.sets[j];
        await client.query(
          `INSERT INTO sets (id, workout_exercise_id, set_no, reps, weight, rpe, rest_seconds)
           VALUES ($1,$2,$3,$4,$5,$6,$7)`,
           [uuidv4(), exId, s.set_no || (j+1), s.reps || 0, s.weight || 0, s.rpe || null, s.rest_seconds || null]
        );
      }
    }
    res.json({ id: workoutId });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'create_workout_failed' });
  } finally {
    client.release();
  }
});

// Publish workout as post and update challenges (workouts_count)
app.post('/api/workouts/:id/publish', requireAuth(pool), async (req, res) => {
  const workoutId = req.params.id;
  const { caption } = req.body;
  const userId = req.user.id;
  const client = await pool.connect();
  try {
    const postId = uuidv4();
    await client.query(
      `INSERT INTO posts (id, author_id, type, linked_workout_id, caption, visibility_status, created_at)
       VALUES ($1,$2,'workout',$3,$4,'visible', now())`,
       [postId, userId, workoutId, caption || null]
    );
    // Update challenges of type workouts_count where user is participant and challenge active
    try {
      const now = new Date();
      const challengeRows = await client.query(`SELECT c.id FROM challenges c JOIN challenge_participants cp ON cp.challenge_id = c.id WHERE cp.user_id = $1 AND c.goal_type = 'workouts_count' AND c.start_date <= now() AND c.end_date >= now()`, [userId]);
      for (let r of challengeRows.rows) {
        await client.query(`UPDATE challenge_participants SET progress_value = progress_value + 1 WHERE challenge_id = $1 AND user_id = $2`, [r.id, userId]);
      }
    } catch (e) {
      console.error('challenge update failed', e);
    }
    res.json({ id: postId });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'publish_failed' });
  } finally {
    client.release();
  }
});

// Uploads, likes, comments, follows, notifications endpoints
app.post('/api/posts/:id/like', requireAuth(pool), async (req, res) => {
  const postId = req.params.id;
  const userId = req.user.id;
  const client = await pool.connect();
  try {
    const exists = await client.query('SELECT id FROM likes WHERE post_id=$1 AND user_id=$2', [postId, userId]);
    if (exists.rowCount > 0) {
      await client.query('DELETE FROM likes WHERE post_id=$1 AND user_id=$2', [postId, userId]);
      await client.query('UPDATE posts SET likes_count = GREATEST(coalesce(likes_count,0)-1,0) WHERE id=$1', [postId]);
      return res.json({ liked: false });
    }
    const lid = uuidv4();
    await client.query('INSERT INTO likes (id, post_id, user_id) VALUES ($1,$2,$3)', [lid, postId, userId]);
    await client.query('UPDATE posts SET likes_count = coalesce(likes_count,0)+1 WHERE id=$1', [postId]);
    const pr = await client.query('SELECT author_id FROM posts WHERE id=$1', [postId]);
    if (pr.rowCount>0) {
      const author = pr.rows[0].author_id;
      if (author !== userId) {
        await client.query("INSERT INTO notifications (id,user_id,actor_id,verb,target_type,target_id,data) VALUES ($1,$2,$3,'like','post',$4,$5)", [uuidv4(), author, userId, postId, JSON.stringify({})]);
      }
    }
    res.json({ liked: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'like_failed' }); } finally { client.release(); }
});

app.post('/api/posts/:id/comments', requireAuth(pool), async (req, res) => {
  const postId = req.params.id;
  const userId = req.user.id;
  const { text } = req.body;
  if (!text || text.trim() === '') return res.status(400).json({ error: 'empty_comment' });
  const client = await pool.connect();
  try {
    const cid = uuidv4();
    await client.query('INSERT INTO comments (id, post_id, user_id, text) VALUES ($1,$2,$3,$4)', [cid, postId, userId, text]);
    await client.query('UPDATE posts SET comments_count = coalesce(comments_count,0)+1 WHERE id=$1', [postId]);
    const pr = await client.query('SELECT author_id FROM posts WHERE id=$1', [postId]);
    if (pr.rowCount>0) {
      const author = pr.rows[0].author_id;
      if (author !== userId) {
        await client.query("INSERT INTO notifications (id,user_id,actor_id,verb,target_type,target_id,data) VALUES ($1,$2,$3,'comment','post',$4,$5)", [uuidv4(), author, userId, postId, JSON.stringify({ text })]);
      }
    }
    res.json({ id: cid, post_id: postId, user_id: userId, text });
  } catch (e) { console.error(e); res.status(500).json({ error: 'comment_failed' }); } finally { client.release(); }
});

app.get('/api/posts/:id/comments', async (req, res) => {
  const postId = req.params.id;
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT c.id, c.text, c.created_at, u.id as user_id, u.username, u.display_name FROM comments c JOIN users u ON u.id = c.user_id WHERE c.post_id = $1 ORDER BY c.created_at ASC`, [postId]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'comments_fetch_failed' }); } finally { client.release(); }
});

app.post('/api/users/:id/follow', requireAuth(pool), async (req, res) => {
  const target = req.params.id;
  const me = req.user.id;
  if (me === target) return res.status(400).json({ error: 'cannot_follow_self' });
  const client = await pool.connect();
  try {
    await client.query('INSERT INTO follows (id, follower_id, followee_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [uuidv4(), me, target]);
    await client.query("INSERT INTO notifications (id,user_id,actor_id,verb,target_type,target_id,data) VALUES ($1,$2,$3,'follow','user',$4,$5)", [uuidv4(), target, me, target, JSON.stringify({})]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'follow_failed' }); } finally { client.release(); }
});

app.post('/api/users/:id/unfollow', requireAuth(pool), async (req, res) => {
  const target = req.params.id;
  const me = req.user.id;
  const client = await pool.connect();
  try {
    await client.query('DELETE FROM follows WHERE follower_id=$1 AND followee_id=$2', [me, target]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'unfollow_failed' }); } finally { client.release(); }
});

app.get('/api/users/:id/followers', async (req, res) => {
  const id = req.params.id;
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT u.id, u.username, u.display_name FROM follows f JOIN users u ON u.id = f.follower_id WHERE f.followee_id = $1`, [id]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'followers_failed' }); } finally { client.release(); }
});
app.get('/api/users/:id/following', async (req, res) => {
  const id = req.params.id;
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT u.id, u.username, u.display_name FROM follows f JOIN users u ON u.id = f.followee_id WHERE f.follower_id = $1`, [id]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'following_failed' }); } finally { client.release(); }
});

app.get('/api/notifications', requireAuth(pool), async (req, res) => {
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT n.id, n.verb, n.target_type, n.target_id, n.data, n.is_read, n.created_at, a.id as actor_id, a.username, a.display_name FROM notifications n LEFT JOIN users a ON a.id = n.actor_id WHERE n.user_id = $1 ORDER BY n.created_at DESC LIMIT 100`, [req.user.id]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'notifications_failed' }); } finally { client.release(); }
});

app.post('/api/notifications/:id/read', requireAuth(pool), async (req, res) => {
  const id = req.params.id;
  const client = await pool.connect();
  try {
    await client.query('UPDATE notifications SET is_read = true WHERE id = $1', [id]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'mark_read_failed' }); } finally { client.release(); }
});

// === Challenges endpoints ===
const authHelpers = auth;
app.post('/api/challenges', requireAuth(pool), async (req,res)=>{
  const client = await pool.connect();
  try {
    const {title,description,start_date,end_date,goal_type,goal_value,gym_id,visibility} = req.body;
    if(!title||!start_date||!end_date||!goal_type) return res.status(400).json({ error: "missing_fields" });
    const cid = uuidv4();
    await client.query(`INSERT INTO challenges (id, creator_user_id, gym_id, title, description, start_date, end_date, goal_type, goal_value, visibility) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [cid, req.user.id, gym_id || null, title, description || null, start_date, end_date, goal_type, goal_value || 0, visibility || 'public']);
    res.json({ id: cid });
  } catch(e){ console.error(e); res.status(500).json({ error: "create_challenge_failed" }); } finally{ client.release(); }
});

app.post('/api/challenges/:id/join', requireAuth(pool), async (req,res)=>{
  const client = await pool.connect();
  try {
    const cid=req.params.id;
    await client.query('INSERT INTO challenge_participants (id, challenge_id, user_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [uuidv4(), cid, req.user.id]);
    res.json({ ok:true });
  } catch(e){ console.error(e); res.status(500).json({ error: "join_failed" }); } finally{ client.release(); }
});

app.get('/api/challenges/public', async (req,res)=>{ const client = await pool.connect(); try{ const r = await client.query('SELECT * FROM challenges WHERE visibility = $1 ORDER BY start_date DESC LIMIT 100', ['public']); res.json(r.rows); }catch(e){ console.error(e); res.status(500).json({ error: "challenges_list_failed" }); } finally{ client.release(); } });
app.get('/api/challenges/gym/:id', async (req,res)=>{ const client = await pool.connect(); try{ const r = await client.query('SELECT * FROM challenges WHERE gym_id = $1 ORDER BY start_date DESC LIMIT 100', [req.params.id]); res.json(r.rows); }catch(e){ console.error(e); res.status(500).json({ error: "challenges_gym_failed" }); } finally{ client.release(); } });
app.get('/api/challenges/:id', async (req,res)=>{ const client = await pool.connect(); try{ const r = await client.query('SELECT * FROM challenges WHERE id = $1 LIMIT 1', [req.params.id]); if(r.rowCount===0) return res.status(404).json({ error:"not_found"}); const c = r.rows[0]; const p = await client.query('SELECT count(*) as participants FROM challenge_participants WHERE challenge_id = $1',[req.params.id]); c.participants = parseInt(p.rows[0].participants,10)||0; res.json(c); }catch(e){ console.error(e); res.status(500).json({ error: "challenge_detail_failed" }); } finally{ client.release(); } });
app.get('/api/challenges/:id/leaderboard', async (req,res)=>{ const client = await pool.connect(); try{ const r = await client.query('SELECT cp.user_id, cp.progress_value, u.username, u.display_name, u.avatar_url FROM challenge_participants cp JOIN users u ON u.id = cp.user_id WHERE cp.challenge_id = $1 ORDER BY cp.progress_value DESC LIMIT 100', [req.params.id]); res.json(r.rows); }catch(e){ console.error(e); res.status(500).json({ error: "leaderboard_failed" }); } finally{ client.release(); } });

// Simple health
app.get('/api/health', (req,res)=>res.json({ ok: true }));

const PORT = process.env.PORT || 4000;
app.listen(PORT, ()=> console.log('Server running on port', PORT));
JS

# -----------------------
# BACKEND: Dockerfile & entrypoint
# -----------------------
cat > "$ROOT/backend/Dockerfile" <<'DOCK'
FROM node:18-alpine
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 4000
CMD ["node", "server.js"]
DOCK

cat > "$ROOT/backend/entrypoint.sh" <<'SH'
#!/bin/sh
set -e
echo "Waiting for database to be ready..."
retries=0
until pg_isready -q -d "$DATABASE_URL"; do
  retries=$((retries+1))
  echo "Postgres is unavailable - sleeping (attempt $retries)..."
  sleep 2
  if [ $retries -gt 60 ]; then
    echo "Postgres did not become available in time, exiting."
    exit 1
  fi
done
echo "Running migrations..."
if [ -n "$DATABASE_URL" ]; then
  psql "$DATABASE_URL" -f migrations/001_create_schema.sql || true
  psql "$DATABASE_URL" -f migrations/002_refresh_tokens.sql || true
  psql "$DATABASE_URL" -f migrations/003_social.sql || true
  psql "$DATABASE_URL" -f migrations/004_challenges.sql || true
  psql "$DATABASE_URL" -f seeds/001_seed_demo.sql || true
else
  echo "DATABASE_URL not set, skipping migrations"
fi
echo "Starting server..."
exec node server.js
SH
chmod +x "$ROOT/backend/entrypoint.sh"

# -----------------------
# BACKEND: README note
# -----------------------
cat > "$ROOT/backend/README.md" <<'MD'
Backend: Express + Postgres
Set DATABASE_URL and JWT_SECRET in .env and run.
Docker: docker-compose in project root can run Postgres + backend.
MD

# -----------------------
# FRONTEND: package.json (Expo minimal)
# -----------------------
cat > "$ROOT/frontend/package.json" <<'JSON'
{
  "name": "fitness-social-frontend",
  "version": "1.0.0",
  "main": "App.js",
  "scripts": {
    "start": "expo start"
  },
  "dependencies": {
    "expo": "~48.0.0",
    "react": "18.2.0",
    "react-native": "0.71.8",
    "@react-navigation/native": "^6.1.6",
    "@react-navigation/native-stack": "^6.9.12",
    "@react-native-async-storage/async-storage": "^1.17.11",
    "react-native-toast-message": "^2.1.5",
    "expo-image-picker": "~14.1.1"
  }
}
JSON

# -----------------------
# FRONTEND: services/api.js (core client wrapper)
# -----------------------
cat > "$ROOT/frontend/services/api.js" <<'JS'
import AsyncStorage from '@react-native-async-storage/async-storage';

const API_BASE = process.env.API_BASE || 'http://10.0.2.2:4000';

async function getToken() {
  return AsyncStorage.getItem('auth_token');
}
async function getRefreshToken() {
  return AsyncStorage.getItem('refresh_token');
}
async function setRefreshToken(t) {
  if (t) await AsyncStorage.setItem('refresh_token', t); else await AsyncStorage.removeItem('refresh_token');
}

async function request(path, options = {}, retry=true) {
  options.headers = options.headers || {};
  const token = await getToken();
  options.headers['Content-Type'] = options.headers['Content-Type'] || 'application/json';
  if (token) options.headers['Authorization'] = 'Bearer ' + token;
  const res = await fetch(API_BASE + path, { ...options, headers: options.headers });
  if (res.status === 401 && retry) {
    const currentRetries = parseInt(options.headers['x-retry-count'] || '0', 10);
    if (currentRetries >= 1) {
      await AsyncStorage.removeItem('auth_token');
      await AsyncStorage.removeItem('refresh_token');
      const txt = await res.text();
      let err = txt;
      try { err = JSON.parse(txt); } catch(e){}
      throw err;
    }
    const refreshToken = await getRefreshToken();
    if (refreshToken) {
      try {
        const r = await fetch(API_BASE + '/api/auth/refresh', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ refreshToken }) });
        if (r.ok) {
          const data = await r.json();
          if (data.token) {
            await AsyncStorage.setItem('auth_token', data.token);
            options.headers['x-retry-count'] = String(currentRetries + 1);
            return request(path, options, false);
          }
        } else {
          await AsyncStorage.removeItem('auth_token');
          await AsyncStorage.removeItem('refresh_token');
        }
      } catch (e) {
        console.error('refresh failed', e);
      }
    }
  }
  if (!res.ok) {
    const txt = await res.text();
    let err = txt;
    try { err = JSON.parse(txt); } catch(e){}
    throw err;
  }
  if (res.status === 204) return null;
  return res.json();
}

export async function apiRegister({username, email, password, display_name}) {
  const res = await request('/api/auth/register', { method: 'POST', body: JSON.stringify({username,email,password,display_name}) }, false);
  if (res.token) {
    await AsyncStorage.setItem('auth_token', res.token);
    await setRefreshToken(res.refreshToken);
  }
  return res;
}

export async function apiLogin({username, email, password}) {
  const res = await request('/api/auth/login', { method: 'POST', body: JSON.stringify({username,email,password}) }, false);
  if (res.token) {
    await AsyncStorage.setItem('auth_token', res.token);
    await setRefreshToken(res.refreshToken);
  }
  return res;
}

export async function apiLogout() {
  const refreshToken = await getRefreshToken();
  try {
    await request('/api/auth/logout', { method: 'POST', body: JSON.stringify({ refreshToken }) }, false);
  } catch (e) {
    console.warn('logout request failed', e);
  }
  await AsyncStorage.removeItem('auth_token');
  await setRefreshToken(null);
}

export async function apiFetchFeed(query) {
  return request('/api/feed' + (query || ''));
}

export async function apiCreateWorkout(payload) {
  return request('/api/workouts', { method: 'POST', body: JSON.stringify(payload) });
}

export async function apiPublishWorkout(workoutId, caption) {
  return request(`/api/workouts/${workoutId}/publish`, { method: 'POST', body: JSON.stringify({ caption }) });
}

export async function apiUploadFile(uri) {
  const token = await getToken();
  const formData = new FormData();
  const filename = uri.split('/').pop();
  const match = /\.(\w+)$/.exec(filename || '');
  const type = match ? `image/${match[1]}` : 'image';
  formData.append('file', { uri, name: filename, type });
  const res = await fetch(API_BASE + '/api/upload', { method: 'POST', headers: { 'Authorization': token ? 'Bearer ' + token : '' }, body: formData });
  if (!res.ok) { const txt = await res.text(); throw txt; }
  return res.json();
}

export async function apiFetchUser() {
  return request('/api/user/me');
}

export async function apiUpdateProfile(payload) {
  return request('/api/user/me', { method: 'PUT', body: JSON.stringify(payload) });
}

/* Social APIs */
export async function apiToggleLike(postId) { return request(`/api/posts/${postId}/like`, { method: 'POST' }); }
export async function apiPostComment(postId, text) { return request(`/api/posts/${postId}/comments`, { method: 'POST', body: JSON.stringify({ text }) }); }
export async function apiGetComments(postId) { return request(`/api/posts/${postId}/comments`); }
export async function apiFollow(userId) { return request(`/api/users/${userId}/follow`, { method: 'POST' }); }
export async function apiUnfollow(userId) { return request(`/api/users/${userId}/unfollow`, { method: 'POST' }); }
export async function apiGetNotifications() { return request('/api/notifications'); }
export async function apiMarkNotificationRead(id) { return request(`/api/notifications/${id}/read`, { method: 'POST' }); }

/* Gyms (B1) */
export async function apiGetGymsNearby(lat, lng) { const q = lat && lng ? `?lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lng)}` : ''; return request(`/api/gyms/nearby${q}`); }
export async function apiGetGym(id) { return request(`/api/gyms/${id}`); }
export async function apiGetGymMembers(id) { return request(`/api/gyms/${id}/members`); }
export async function apiJoinGym(id) { return request(`/api/gyms/${id}/join`, { method: 'POST' }); }

/* Challenges (B2) */
export async function apiCreateChallenge(payload) { return request('/api/challenges', { method: 'POST', body: JSON.stringify(payload) }); }
export async function apiJoinChallenge(id) { return request(`/api/challenges/${id}/join`, { method: 'POST' }); }
export async function apiListPublicChallenges() { return request('/api/challenges/public'); }
export async function apiListGymChallenges(gymId) { return request(`/api/challenges/gym/${gymId}`); }
export async function apiGetChallenge(id) { return request(`/api/challenges/${id}`); }
export async function apiGetChallengeLeaderboard(id) { return request(`/api/challenges/${id}/leaderboard`); }
JS

# -----------------------
# FRONTEND: AuthContext, basic screens (Login/Register), Feed, PostCard, Profile, ProfileEdit, Gym + Challenges screens
# (We'll create minimal but functional files)
# -----------------------
cat > "$ROOT/frontend/services/AuthContext.js" <<'JS'
import React, { createContext, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { apiLogin, apiRegister, apiLogout } from './api';

export const AuthContext = createContext();

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const token = await AsyncStorage.getItem('auth_token');
      const userJson = await AsyncStorage.getItem('auth_user');
      if (token && userJson) {
        setUser(JSON.parse(userJson));
      }
      setLoading(false);
    }
    load();
  }, []);

  async function signIn({ username, email, password }) {
    const res = await apiLogin({ username, email, password });
    if (res && res.token) {
      await AsyncStorage.setItem('auth_token', res.token);
      await AsyncStorage.setItem('auth_user', JSON.stringify(res.user));
      setUser(res.user);
      return res.user;
    }
    throw new Error('Login failed');
  }

  async function signUp({ username, email, password, display_name }) {
    const res = await apiRegister({ username, email, password, display_name });
    if (res && res.token) {
      await AsyncStorage.setItem('auth_token', res.token);
      await AsyncStorage.setItem('auth_user', JSON.stringify(res.user));
      setUser(res.user);
      return res.user;
    }
    throw new Error('Registration failed');
  }

  async function signOut() {
    try {
      await apiLogout();
    } catch (e) {
      console.warn('logout error', e);
    }
    await AsyncStorage.removeItem('auth_token');
    await AsyncStorage.removeItem('auth_user');
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, loading, signIn, signUp, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}
JS

# Minimal UI screens: App.js, FeedScreen, PostCard, ProfileScreen, ProfileEditScreen, GymDiscovery/GymDetail, Comments, Notifications, Challenge screens
cat > "$ROOT/frontend/App.js" <<'JS'
import React, { useContext } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import FeedScreen from './screens/FeedScreen';
import LoginScreen from './screens/LoginScreen';
import RegisterScreen from './screens/RegisterScreen';
import ProfileScreen from './screens/ProfileScreen';
import ProfileEditScreen from './screens/ProfileEditScreen';
import GymDiscoveryScreen from './screens/GymDiscoveryScreen';
import GymDetailScreen from './screens/GymDetailScreen';
import CommentsScreen from './screens/CommentsScreen';
import NotificationsScreen from './screens/NotificationsScreen';
import ChallengeListScreen from './screens/ChallengeListScreen';
import ChallengeCreateScreen from './screens/ChallengeCreateScreen';
import ChallengeDetailScreen from './screens/ChallengeDetailScreen';
import ChallengeLeaderboardScreen from './screens/ChallengeLeaderboardScreen';
import { AuthProvider, AuthContext } from './services/AuthContext';
import Toast from 'react-native-toast-message';

const Stack = createNativeStackNavigator();

function AppStack() {
  return (
    <Stack.Navigator initialRouteName="Feed">
      <Stack.Screen name="Feed" component={FeedScreen} />
      <Stack.Screen name="Profile" component={ProfileScreen} />
      <Stack.Screen name="ProfileEdit" component={ProfileEditScreen} />
      <Stack.Screen name="GymDiscovery" component={GymDiscoveryScreen} options={{title: 'Find Gyms'}} />
      <Stack.Screen name="GymDetail" component={GymDetailScreen} options={{title: 'Gym'}} />
      <Stack.Screen name="Comments" component={CommentsScreen} options={{title: 'Comments'}} />
      <Stack.Screen name="Notifications" component={NotificationsScreen} options={{title: 'Notifications'}} />
      <Stack.Screen name="Challenges" component={ChallengeListScreen} options={{title: 'Challenges'}} />
      <Stack.Screen name="ChallengeCreate" component={ChallengeCreateScreen} options={{title: 'Create Challenge'}} />
      <Stack.Screen name="ChallengeDetail" component={ChallengeDetailScreen} options={{title: 'Challenge'}} />
      <Stack.Screen name="ChallengeLeaderboard" component={ChallengeLeaderboardScreen} options={{title: 'Leaderboard'}} />
    </Stack.Navigator>
  );
}

function AuthStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="Login" component={LoginScreen} />
      <Stack.Screen name="Register" component={RegisterScreen} />
    </Stack.Navigator>
  );
}

function RootNavigator() {
  const { user, loading } = useContext(AuthContext);
  if (loading) return null;
  return user ? <AppStack /> : <AuthStack />;
}

export default function App() {
  return (
    <AuthProvider>
      <NavigationContainer>
        <RootNavigator />
      </NavigationContainer>
      <Toast />
    </AuthProvider>
  );
}
JS

# Create simple screen stubs (keeping them minimal so app runs)
cat > "$ROOT/frontend/screens/LoginScreen.js" <<'JS'
import React, { useState, useContext } from 'react';
import { View, TextInput, Button } from 'react-native';
import { AuthContext } from '../services/AuthContext';

export default function LoginScreen() {
  const { signIn } = useContext(AuthContext);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  return (
    <View style={{padding:12}}>
      <TextInput placeholder="username or email" value={username} onChangeText={setUsername} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}}/>
      <TextInput placeholder="password" secureTextEntry value={password} onChangeText={setPassword} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}}/>
      <Button title="Login" onPress={()=>signIn({ username, password })}/>
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/RegisterScreen.js" <<'JS'
import React, { useState, useContext } from 'react';
import { View, TextInput, Button } from 'react-native';
import { AuthContext } from '../services/AuthContext';

export default function RegisterScreen() {
  const { signUp } = useContext(AuthContext);
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  return (
    <View style={{padding:12}}>
      <TextInput placeholder="username" value={username} onChangeText={setUsername} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}}/>
      <TextInput placeholder="email" value={email} onChangeText={setEmail} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}}/>
      <TextInput placeholder="password" secureTextEntry value={password} onChangeText={setPassword} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}}/>
      <Button title="Register" onPress={()=>signUp({ username, email, password })}/>
    </View>
  );
}
JS

cat > "$ROOT/frontend/components/PostCard.js" <<'JS'
import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { apiToggleLike } from '../services/api';

export default function PostCard({post}) {
  const navigation = useNavigation();
  const [likes, setLikes] = useState(post.likes_count || 0);
  const [commentsCount, setCommentsCount] = useState(post.comments_count || 0);
  const [liked, setLiked] = useState(false);

  async function onLike() {
    try {
      const res = await apiToggleLike(post.id);
      setLiked(res.liked);
      setLikes(prev => res.liked ? prev + 1 : Math.max(prev - 1, 0));
    } catch (e) { console.error('like error', e); }
  }

  return (
    <View style={styles.card}>
      <Text style={styles.author}>{post.author.displayName} • {new Date(post.createdAt).toLocaleString()}</Text>
      <Text style={styles.caption}>{post.caption}</Text>
      <View style={styles.workoutSummary}>
        <Text style={styles.wTitle}>{post.workout.title || 'Workout'}</Text>
      </View>
      <View style={styles.actions}>
        <TouchableOpacity onPress={onLike}><Text>{liked ? '❤️' : '🤍'} {likes}</Text></TouchableOpacity>
        <TouchableOpacity onPress={() => navigation.navigate('Comments', { postId: post.id })}><Text>💬 {commentsCount}</Text></TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { padding: 12, borderBottomWidth: 1, borderColor: '#eee' },
  author: { fontWeight: '600', marginBottom: 6 },
  caption: { marginBottom: 8 },
  workoutSummary: { backgroundColor: '#fafafa', padding: 8, borderRadius: 6 },
  wTitle: { fontWeight: '700' },
  actions: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 8 }
});
JS

cat > "$ROOT/frontend/screens/FeedScreen.js" <<'JS'
import React, {useEffect, useState, useContext} from 'react';
import { View, Text, FlatList, Button } from 'react-native';
import PostCard from '../components/PostCard';
import { apiFetchFeed } from '../services/api';
import { AuthContext } from '../services/AuthContext';

export default function FeedScreen({navigation}) {
  const [posts, setPosts] = useState([]);
  const { user } = useContext(AuthContext);
  const [feedScope, setFeedScope] = React.useState('global');

  const load = async ()=>{ try { const data = await apiFetchFeed(feedScope === 'local' ? '?scope=local' : ''); setPosts(data); } catch(e){ console.error(e); } };

  useEffect(()=>{
    navigation.setOptions({
      headerRight: () => (
        <Button title="Profile" onPress={() => navigation.navigate('Profile')} />
      ),
    });
    const unsub = navigation.addListener('focus', load);
    load();
    return unsub;
  }, [navigation, feedScope]);

  return (
    <View style={{flex:1}}>
      <View style={{padding:12}}>
        <View style={{flexDirection:'row', marginBottom:8}}>
          <Button title="Global" onPress={() => { setFeedScope('global'); load(); }} />
          <View style={{width:8}} />
          <Button title="Local" onPress={() => { setFeedScope('local'); load(); }} />
          <View style={{width:8}} />
          <Button title="Find Gyms" onPress={() => navigation.navigate('GymDiscovery')} />
        </View>
        <Button title="Start Workout" onPress={()=>{}} />
        <View style={{height:8}} />
        <Text>Signed in as: {user?.display_name || user?.username}</Text>
      </View>
      <FlatList
        data={posts}
        keyExtractor={(item)=>String(item.id)}
        renderItem={({item})=> <PostCard post={item} />}
      />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/ProfileScreen.js" <<'JS'
import React, { useContext } from 'react';
import { View, Text, Button } from 'react-native';
import { AuthContext } from '../services/AuthContext';

export default function ProfileScreen({ navigation }) {
  const { user, signOut } = useContext(AuthContext);

  return (
    <View style={{padding:12}}>
      <Text>Username: {user?.username}</Text>
      <Text>Display Name: {user?.display_name || user?.displayName}</Text>
      <Text>Email: {user?.email}</Text>
      <View style={{height:12}} />
      <Button title="Edit Profile" onPress={() => navigation.navigate('ProfileEdit')} />
      <View style={{height:12}} />
      <Button title="Logout" color="red" onPress={() => signOut()} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/ProfileEditScreen.js" <<'JS'
import React, { useState, useEffect, useContext } from 'react';
import { View, Text, TextInput, Button, Image, Alert } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { AuthContext } from '../services/AuthContext';
import { apiUploadFile, apiUpdateProfile } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ProfileEditScreen({ navigation }) {
  const { user } = useContext(AuthContext);
  const [displayName, setDisplayName] = useState(user?.display_name || user?.username || '');
  const [avatar, setAvatar] = useState(user?.avatar_url || null);

  async function pickImage() {
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      Alert.alert('Permission required', 'Allow access to photos to upload an avatar');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({ base64: false, quality: 0.7, allowsEditing: true });
    if (result.cancelled) return;
    try {
      const uploadRes = await apiUploadFile(result.uri);
      setAvatar(uploadRes.url);
      Toast.show({ type: 'success', text1: 'Uploaded avatar' });
    } catch (e) {
      console.error(e);
      Toast.show({ type: 'error', text1: 'Upload failed' });
    }
  }

  async function saveProfile() {
    try {
      const updated = await apiUpdateProfile({ display_name: displayName, avatar_url: avatar });
      Toast.show({ type: 'success', text1: 'Profile updated' });
      navigation.goBack();
    } catch (e) {
      console.error(e);
      Toast.show({ type: 'error', text1: 'Update failed' });
    }
  }

  return (
    <View style={{padding:12}}>
      {avatar ? <Image source={{ uri: avatar }} style={{ width: 120, height: 120, borderRadius: 60, marginBottom:12 }} /> : <View style={{ width:120, height:120, backgroundColor:'#eee', marginBottom:12 }} /> }
      <Button title={avatar ? 'Change Avatar' : 'Upload Avatar'} onPress={pickImage} />
      <View style={{height:12}} />
      <Text>Display name</Text>
      <TextInput value={displayName} onChangeText={setDisplayName} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:12}} />
      <Button title="Save" onPress={saveProfile} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/GymDiscoveryScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, Button, TextInput } from 'react-native';
import { apiGetGymsNearby } from '../services/api';

export default function GymDiscoveryScreen({ navigation }) {
  const [lat, setLat] = useState('');
  const [lng, setLng] = useState('');
  const [gyms, setGyms] = useState([]);

  async function load() {
    try {
      const data = await apiGetGymsNearby(lat || undefined, lng || undefined);
      setGyms(data);
    } catch (e) { console.error(e); }
  }

  useEffect(()=>{ load(); }, []);

  return (
    <View style={{flex:1,padding:12}}>
      <Text>Find gyms nearby (enter coords or leave blank):</Text>
      <View style={{flexDirection:'row', marginVertical:8}}>
        <TextInput placeholder="lat" value={lat} onChangeText={setLat} style={{flex:1,borderWidth:1,borderColor:'#ddd',padding:8,marginRight:8}} />
        <TextInput placeholder="lng" value={lng} onChangeText={setLng} style={{flex:1,borderWidth:1,borderColor:'#ddd',padding:8}} />
      </View>
      <Button title="Search" onPress={load} />
      <FlatList data={gyms} keyExtractor={(i)=>i.id} renderItem={({item})=>(
        <View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}>
          <Text style={{fontWeight:'700'}}>{item.name}</Text>
          <Text>{item.address}</Text>
          <Button title="View" onPress={()=>navigation.navigate('GymDetail',{ gymId: item.id })} />
        </View>
      )} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/GymDetailScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, Button, FlatList } from 'react-native';
import { apiGetGym, apiGetGymMembers, apiJoinGym } from '../services/api';
import Toast from 'react-native-toast-message';

export default function GymDetailScreen({ route, navigation }) {
  const { gymId } = route.params;
  const [gym, setGym] = useState(null);
  const [members, setMembers] = useState([]);

  async function load() {
    try {
      const g = await apiGetGym(gymId);
      setGym(g);
      const m = await apiGetGymMembers(gymId);
      setMembers(m);
    } catch (e) { console.error(e); Toast.show({ type: 'error', text1: 'Load failed' }); }
  }

  useEffect(()=>{ load(); }, []);

  async function join() {
    try {
      await apiJoinGym(gymId);
      Toast.show({ type: 'success', text1: 'Joined gym' });
    } catch (e) { Toast.show({ type: 'error', text1: 'Join failed' }); }
  }

  if (!gym) return <View style={{padding:12}}><Text>Loading...</Text></View>;

  return (
    <View style={{flex:1,padding:12}}>
      <Text style={{fontWeight:'800', fontSize:18}}>{gym.name}</Text>
      <Text>{gym.address}</Text>
      <View style={{height:12}} />
      <Button title="Join Gym" onPress={join} />
      <View style={{height:12}} />
      <Text style={{fontWeight:'700'}}>Members</Text>
      <FlatList data={members} keyExtractor={(i)=>i.id} renderItem={({item})=>(
        <View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}><Text style={{fontWeight:'600'}}>{item.display_name || item.username}</Text></View>
      )} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/CommentsScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TextInput, Button } from 'react-native';
import { apiGetComments, apiPostComment } from '../services/api';
import Toast from 'react-native-toast-message';

export default function CommentsScreen({ route }) {
  const { postId } = route.params;
  const [comments, setComments] = useState([]);
  const [text, setText] = useState('');
  useEffect(()=>{ load(); }, []);
  async function load(){ try { const data = await apiGetComments(postId); setComments(data); } catch(e){ console.error(e); } }
  async function submit(){ try { const c = await apiPostComment(postId, text); setComments(prev => [...prev, c]); setText(''); Toast.show({ type: 'success', text1: 'Comment posted' }); } catch(e){ Toast.show({ type: 'error', text1: 'Comment failed' }); } }
  return (
    <View style={{flex:1,padding:12}}>
      <FlatList data={comments} keyExtractor={(i)=>i.id} renderItem={({item})=> (<View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}><Text style={{fontWeight:'600'}}>{item.display_name || item.username}</Text><Text>{item.text}</Text></View>)} />
      <TextInput value={text} onChangeText={setText} placeholder="Write a comment" style={{borderWidth:1,borderColor:'#ddd',padding:8,marginVertical:8}} />
      <Button title="Post Comment" onPress={submit} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/NotificationsScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, Button } from 'react-native';
import { apiGetNotifications, apiMarkNotificationRead } from '../services/api';
import Toast from 'react-native-toast-message';

export default function NotificationsScreen() {
  const [notifs, setNotifs] = useState([]);
  useEffect(()=>{ load(); }, []);
  async function load(){ try { const data = await apiGetNotifications(); setNotifs(data); } catch(e){ console.error(e); } }
  async function markRead(id){ try { await apiMarkNotificationRead(id); Toast.show({ type: 'success', text1: 'Marked read' }); load(); } catch(e){ Toast.show({ type: 'error', text1: 'Action failed' }); } }
  return (
    <View style={{flex:1,padding:12}}>
      <FlatList data={notifs} keyExtractor={(i)=>i.id} renderItem={({item})=> (
        <View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}>
          <Text style={{fontWeight:'700'}}>{item.verb} • {item.display_name || item.username}</Text>
          <Text>{item.data && item.data.text}</Text>
          {!item.is_read && <Button title="Mark read" onPress={()=>markRead(item.id)} />}
        </View>
      )} />
    </View>
  );
}
JS

# Challenges screens
cat > "$ROOT/frontend/screens/ChallengeListScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, Button } from 'react-native';
import { apiListPublicChallenges } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ChallengeListScreen({ navigation }) {
  const [publicChallenges, setPublicChallenges] = useState([]);
  async function load() {
    try {
      const p = await apiListPublicChallenges();
      setPublicChallenges(p || []);
    } catch (e) { console.error(e); Toast.show({ type: 'error', text1: 'Load failed' }); }
  }
  useEffect(()=>{ load(); }, []);
  return (
    <View style={{flex:1,padding:12}}>
      <Button title="Create Challenge" onPress={() => navigation.navigate('ChallengeCreate')} />
      <View style={{height:12}} />
      <Text style={{fontWeight:'800'}}>Public Challenges</Text>
      <FlatList data={publicChallenges} keyExtractor={(i)=>i.id} renderItem={({item})=>(
        <View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}>
          <Text style={{fontWeight:'700'}}>{item.title}</Text>
          <Text>{item.description}</Text>
          <Button title="View" onPress={()=>navigation.navigate('ChallengeDetail',{challengeId: item.id})} />
        </View>
      )} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/ChallengeCreateScreen.js" <<'JS'
import React, { useState } from 'react';
import { View, Text, TextInput, Button } from 'react-native';
import { apiCreateChallenge } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ChallengeCreateScreen({ navigation }) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [goalValue, setGoalValue] = useState('7');
  async function create() {
    try {
      const payload = {
        title,
        description,
        start_date: new Date().toISOString(),
        end_date: new Date(Date.now() + 7*24*3600*1000).toISOString(),
        goal_type: 'workouts_count',
        goal_value: parseInt(goalValue,10) || 7,
        visibility: 'public'
      };
      const r = await apiCreateChallenge(payload);
      Toast.show({ type: 'success', text1: 'Created' });
      navigation.navigate('ChallengeDetail', { challengeId: r.id });
    } catch (e) {
      console.error(e);
      Toast.show({ type: 'error', text1: 'Create failed' });
    }
  }

  return (
    <View style={{flex:1,padding:12}}>
      <Text>Title</Text>
      <TextInput value={title} onChangeText={setTitle} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} />
      <Text>Description</Text>
      <TextInput value={description} onChangeText={setDescription} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} multiline />
      <Text>Goal (workouts_count)</Text>
      <TextInput value={goalValue} onChangeText={setGoalValue} keyboardType="numeric" style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} />
      <Button title="Create Challenge" onPress={create} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/ChallengeDetailScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, Button } from 'react-native';
import { apiGetChallenge, apiJoinChallenge } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ChallengeDetailScreen({ route, navigation }) {
  const { challengeId } = route.params;
  const [challenge, setChallenge] = useState(null);

  async function load() {
    try {
      const c = await apiGetChallenge(challengeId);
      setChallenge(c);
    } catch (e) { console.error(e); Toast.show({ type: 'error', text1: 'Load failed' }); }
  }

  useEffect(()=>{ load(); }, []);

  async function join() {
    try {
      await apiJoinChallenge(challengeId);
      Toast.show({ type: 'success', text1: 'Joined' });
    } catch (e) { Toast.show({ type: 'error', text1: 'Join failed' }); }
  }

  if (!challenge) return <View style={{padding:12}}><Text>Loading...</Text></View>;

  return (
    <View style={{flex:1,padding:12}}>
      <Text style={{fontWeight:'800', fontSize:18}}>{challenge.title}</Text>
      <Text>{challenge.description}</Text>
      <Text>Goal: {challenge.goal_type} — {challenge.goal_value}</Text>
      <Text>Participants: {challenge.participants}</Text>
      <View style={{height:12}} />
      <Button title="Join Challenge" onPress={join} />
      <View style={{height:12}} />
      <Button title="Leaderboard" onPress={()=>navigation.navigate('ChallengeLeaderboard', { challengeId })} />
    </View>
  );
}
JS

cat > "$ROOT/frontend/screens/ChallengeLeaderboardScreen.js" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList } from 'react-native';
import { apiGetChallengeLeaderboard } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ChallengeLeaderboardScreen({ route }) {
  const { challengeId } = route.params;
  const [items, setItems] = useState([]);

  async function load() {
    try {
      const r = await apiGetChallengeLeaderboard(challengeId);
      setItems(r || []);
    } catch (e) { console.error(e); Toast.show({ type: 'error', text1: 'Load failed' }); }
  }

  useEffect(()=>{ load(); }, []);

  return (
    <View style={{flex:1,padding:12}}>
      <FlatList data={items} keyExtractor={(i)=>i.user_id} renderItem={({item, index})=>(
        <View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}>
          <Text style={{fontWeight:'700'}}>{index+1}. {item.display_name || item.username}</Text>
          <Text>Progress: {item.progress_value}</Text>
        </View>
      )} />
    </View>
  );
}
JS

# -----------------------
# FRONTEND: README note
# -----------------------
cat > "$ROOT/frontend/README.md" <<'MD'
Expo frontend.
Run: npm install
Run: expo start
Note: run 'expo install expo-image-picker react-native-toast-message' to add native modules on local machine.
MD

# -----------------------
# Top-level files: docker-compose, README, LICENSE, CI
# -----------------------
cat > "$ROOT/docker-compose.yml" <<'YML'
version: '3.8'
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_DB: fitness_social
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - '5432:5432'
    volumes:
      - db_data:/var/lib/postgresql/data
  backend:
    build: ./backend
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/fitness_social
      JWT_SECRET: supersecret_change_me
      PORT: 4000
    ports:
      - '4000:4000'
    depends_on:
      - db
    entrypoint: ["/usr/src/app/entrypoint.sh"]
volumes:
  db_data:
YML

cat > "$ROOT/README.md" <<'MD'
Fitness Social — Full Project (Auth, Profiles, Workouts, Social, Gyms, Challenges)

Quickstart (Docker):
1. Copy backend/.env.example to backend/.env and set DATABASE_URL if needed.
2. docker-compose up --build
3. Backend will run migrations and seeds automatically.

Quickstart (local):
- Backend: cd backend && npm install && set DATABASE_URL && node server.js
- Frontend: cd frontend && npm install && expo start
MD

cat > "$ROOT/LICENSE" <<'LIC'
MIT License

Copyright (c) 2025 Samir

Permission is hereby granted...
LIC

cat > "$ROOT/.github/workflows/ci.yml" <<'WF'
name: CI
on: [push,pull_request]
jobs:
  backend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: npm ci
  frontend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: npm ci
WF

# -----------------------
# Final: make zip
# -----------------------
echo "Creating ZIP: $ZIP_NAME"
cd "$(dirname "$ROOT")"
rm -f "$ZIP_NAME"
zip -r "$ZIP_NAME" "$(basename "$ROOT")" >/dev/null
echo "Created $ZIP_NAME in $(pwd)"
echo ""
echo "NEXT STEPS:"
echo "1) Unzip the archive or use the created folder $(basename "$ROOT")."
echo "2) Edit backend/.env to set DATABASE_URL and JWT_SECRET (or use docker-compose which uses defaults)."
echo "3) To run with Docker: docker-compose up --build"
echo "4) To run locally: cd backend && npm install && psql \$DATABASE_URL -f migrations/001_create_schema.sql && psql \$DATABASE_URL -f migrations/002_refresh_tokens.sql && psql \$DATABASE_URL -f migrations/003_social.sql && psql \$DATABASE_URL -f migrations/004_challenges.sql && psql \$DATABASE_URL -f seeds/001_seed_demo.sql && npm start"
echo "5) Frontend: cd frontend && npm install && expo start (also run expo install expo-image-picker react-native-toast-message)"
