require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { Pool } = require('pg');
const { v4: uuidv4 } = require('uuid');
const auth = require('./server_auth_helpers/auth');
const multer = require('multer');
const path = require('path');
const requireAuth = require('./middleware/requireAuth');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const app = express();
app.use(cors());
app.use(bodyParser.json());

// Serve uploaded files
const PUBLIC_DIR = path.join(__dirname, 'public');
if (!require('fs').existsSync(path.join(PUBLIC_DIR,'uploads'))) require('fs').mkdirSync(path.join(PUBLIC_DIR,'uploads'), { recursive: true });
app.use('/uploads', express.static(path.join(PUBLIC_DIR,'uploads')));

// setup multer for uploads
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, path.join(PUBLIC_DIR,'uploads'))
  },
  filename: function (req, file, cb) {
    const unique = Date.now() + '-' + Math.round(Math.random()*1E9);
    cb(null, unique + '-' + file.originalname.replace(/[^a-zA-Z0-9.\-\_]/g,'_'))
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
    // generate tokens
    const accessToken = auth.generateAccessToken({ userId: id });
    const refreshToken = auth.generateRefreshToken();
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30); // 30 days
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
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30); // 30 days
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
      // expired - delete
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

// Logout - revoke refresh token
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


// Upload endpoint for avatars/media (multipart/form-data)
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

// Update profile (display_name, avatar_url)
app.put('/api/user/me', requireAuth(pool), async (req, res) => {
  const { display_name, avatar_url } = req.body;
  const client = await pool.connect();
  try {
    await client.query(`UPDATE users SET display_name = COALESCE($1, display_name), avatar_url = COALESCE($2, avatar_url) WHERE id = $3`, [display_name, avatar_url, req.user.id]);
    const r = await client.query('SELECT id, username, display_name, email, avatar_url FROM users WHERE id = $1', [req.user.id]);
    res.json(r.rows[0]);
  } catch (e) { console.error(e); res.status(500).json({ error: 'update_failed' }); } finally { client.release(); }
});

// Public feed (simple)
app.get('/api/feed', async (req, res) => {
  const client = await pool.connect();
  try {
    const r = await client.query(`
      SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title
      FROM posts p
      JOIN users u ON u.id = p.author_id
      LEFT JOIN workouts w ON w.id = p.linked_workout_id
      WHERE p.visibility_status = 'visible'
      ORDER BY p.created_at DESC
      LIMIT 50
    `);
    const posts = r.rows.map(row => ({
      id: row.id,
      caption: row.caption,
      createdAt: row.created_at,
      author: { id: row.author_id, username: row.username, displayName: row.display_name },
      workout: { id: row.workout_id, title: row.workout_title, exercises: [] } // frontend can fetch workout details separately
    }));
    res.json(posts);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'feed_error' });
  } finally {
    client.release();
  }
});

// Protected: create workout
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
    // Insert exercises and sets
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

// Protected: publish workout as post
app.post('/api/workouts/:id/publish', requireAuth(pool), async (req, res) => {
  const workoutId = req.params.id;
  const { caption } = req.body;
  const userId = req.user.id;
  const client = await pool.connect();
  try {
    // create post
    const postId = uuidv4();
    await client.query(
      `INSERT INTO posts (id, author_id, type, linked_workout_id, caption, visibility_status, created_at)
       VALUES ($1,$2,'workout',$3,$4,'visible', now())`,
       [postId, userId, workoutId, caption || null]
    );
    res.json({ id: postId });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'publish_failed' });
  } finally {
    client.release();
  }
});

/* B3_PATCH_MARKER */
/* Advanced publish (publish-metrics): computes total weight & distance and updates challenge progress */
app.post('/api/workouts/:id/publish-metrics', requireAuth(pool), async (req, res) => {
  const workoutId = req.params.id;
  const { caption } = req.body || {};
  const userId = req.user && req.user.id;
  const client = await pool.connect();
  try {
    const postId = require('uuid').v4();
    await client.query(
      `INSERT INTO posts (id, author_id, type, linked_workout_id, caption, visibility_status, created_at)
       VALUES ($1,$2,'workout',$3,$4,'visible', now())`,
       [postId, userId, workoutId, caption || null]
    );

    // compute total weight lifted: sum(reps * weight) across all sets of this workout
    const weightRes = await client.query(`
      SELECT s.reps, s.weight FROM sets s
      JOIN workout_exercises we ON we.id = s.workout_exercise_id
      WHERE we.workout_id = $1
    `, [workoutId]);
    let totalWeight = 0;
    for (let r of weightRes.rows || []) {
      const reps = Number(r.reps || 0);
      const weight = Number(r.weight || 0);
      totalWeight += reps * weight;
    }

    // read workout distance (assumes workouts.distance exists)
    const dres = await client.query('SELECT distance FROM workouts WHERE id = $1 LIMIT 1', [workoutId]);
    const distance = dres.rowCount ? Number(dres.rows[0].distance || 0) : 0;

    // update participants progress for active challenges the user is in
    const challengeRows = await client.query(
      `SELECT c.id, c.goal_type FROM challenges c
       JOIN challenge_participants cp ON cp.challenge_id = c.id
       WHERE cp.user_id = $1 AND c.start_date <= now() AND c.end_date >= now()`,
      [userId]
    );

    for (let ch of challengeRows.rows || []) {
      if (ch.goal_type === 'workouts_count') {
        await client.query(`UPDATE challenge_participants SET progress_value = progress_value + 1 WHERE challenge_id = $1 AND user_id = $2`, [ch.id, userId]);
      } else if (ch.goal_type === 'weight_lifted') {
        if (totalWeight > 0) {
          await client.query(`UPDATE challenge_participants SET progress_value = progress_value + $1 WHERE challenge_id = $2 AND user_id = $3`, [totalWeight, ch.id, userId]);
        }
      } else if (ch.goal_type === 'distance') {
        if (distance > 0) {
          await client.query(`UPDATE challenge_participants SET progress_value = progress_value + $1 WHERE challenge_id = $2 AND user_id = $3`, [distance, ch.id, userId]);
        }
      }
    }

    res.json({ id: postId, totalWeight, distance });
  } catch (e) {
    console.error('publish-metrics failed', e);
    res.status(500).json({ error: 'publish_metrics_failed', message: String(e) });
  } finally {
    client.release();
  }
});

/* Challenge summary endpoint: top participants, your progress, percent complete */
app.get('/api/challenges/:id/summary', requireAuth(pool), async (req, res) => {
  const client = await pool.connect();
  try {
    const cid = req.params.id;
    const r = await client.query('SELECT id, title, description, start_date, end_date, goal_type, goal_value FROM challenges WHERE id = $1 LIMIT 1', [cid]);
    if (r.rowCount === 0) return res.status(404).json({ error: 'not_found' });
    const challenge = r.rows[0];
    const top = await client.query('SELECT cp.user_id, cp.progress_value, u.username, u.display_name, u.avatar_url FROM challenge_participants cp JOIN users u ON u.id = cp.user_id WHERE cp.challenge_id = $1 ORDER BY cp.progress_value DESC LIMIT 10', [cid]);
    const mine = await client.query('SELECT progress_value FROM challenge_participants WHERE challenge_id = $1 AND user_id = $2 LIMIT 1', [cid, req.user.id]);
    const myProgress = mine.rowCount ? Number(mine.rows[0].progress_value) : 0;
    let percent = null;
    if (Number(challenge.goal_value) > 0) percent = Math.min(100, Math.round((myProgress / Number(challenge.goal_value)) * 100));
    res.json({ challenge, top: top.rows, myProgress, percent });
  } catch (e) {
    console.error('challenge summary failed', e);
    res.status(500).json({ error: 'summary_failed' });
  } finally {
    client.release();
  }
});
/* B3_PATCH_MARKER */
/* Advanced publish (publish-metrics): computes total weight & distance and updates challenge progress */
app.post('/api/workouts/:id/publish-metrics', requireAuth(pool), async (req, res) => {
  const workoutId = req.params.id;
  const { caption } = req.body || {};
  const userId = req.user && req.user.id;
  const client = await pool.connect();
  try {
    const postId = require('uuid').v4();
    await client.query(
      `INSERT INTO posts (id, author_id, type, linked_workout_id, caption, visibility_status, created_at)
       VALUES ($1,$2,'workout',$3,$4,'visible', now())`,
       [postId, userId, workoutId, caption || null]
    );

    // compute total weight lifted: sum(reps * weight) across all sets of this workout
    const weightRes = await client.query(`
      SELECT s.reps, s.weight FROM sets s
      JOIN workout_exercises we ON we.id = s.workout_exercise_id
      WHERE we.workout_id = $1
    `, [workoutId]);
    let totalWeight = 0;
    for (let r of weightRes.rows || []) {
      const reps = Number(r.reps || 0);
      const weight = Number(r.weight || 0);
      totalWeight += reps * weight;
    }

    // read workout distance (assumes workouts.distance exists)
    const dres = await client.query('SELECT distance FROM workouts WHERE id = $1 LIMIT 1', [workoutId]);
    const distance = dres.rowCount ? Number(dres.rows[0].distance || 0) : 0;

    // update participants progress for active challenges the user is in
    const challengeRows = await client.query(
      `SELECT c.id, c.goal_type FROM challenges c
       JOIN challenge_participants cp ON cp.challenge_id = c.id
       WHERE cp.user_id = $1 AND c.start_date <= now() AND c.end_date >= now()`,
      [userId]
    );

    for (let ch of challengeRows.rows || []) {
      if (ch.goal_type === 'workouts_count') {
        await client.query(`UPDATE challenge_participants SET progress_value = progress_value + 1 WHERE challenge_id = $1 AND user_id = $2`, [ch.id, userId]);
      } else if (ch.goal_type === 'weight_lifted') {
        if (totalWeight > 0) {
          await client.query(`UPDATE challenge_participants SET progress_value = progress_value + $1 WHERE challenge_id = $2 AND user_id = $3`, [totalWeight, ch.id, userId]);
        }
      } else if (ch.goal_type === 'distance') {
        if (distance > 0) {
          await client.query(`UPDATE challenge_participants SET progress_value = progress_value + $1 WHERE challenge_id = $2 AND user_id = $3`, [distance, ch.id, userId]);
        }
      }
    }

    res.json({ id: postId, totalWeight, distance });
  } catch (e) {
    console.error('publish-metrics failed', e);
    res.status(500).json({ error: 'publish_metrics_failed', message: String(e) });
  } finally {
    client.release();
  }
});

/* Challenge summary endpoint: top participants, your progress, percent complete */
app.get('/api/challenges/:id/summary', requireAuth(pool), async (req, res) => {
  const client = await pool.connect();
  try {
    const cid = req.params.id;
    const r = await client.query('SELECT id, title, description, start_date, end_date, goal_type, goal_value FROM challenges WHERE id = $1 LIMIT 1', [cid]);
    if (r.rowCount === 0) return res.status(404).json({ error: 'not_found' });
    const challenge = r.rows[0];
    const top = await client.query('SELECT cp.user_id, cp.progress_value, u.username, u.display_name, u.avatar_url FROM challenge_participants cp JOIN users u ON u.id = cp.user_id WHERE cp.challenge_id = $1 ORDER BY cp.progress_value DESC LIMIT 10', [cid]);
    const mine = await client.query('SELECT progress_value FROM challenge_participants WHERE challenge_id = $1 AND user_id = $2 LIMIT 1', [cid, req.user.id]);
    const myProgress = mine.rowCount ? Number(mine.rows[0].progress_value) : 0;
    let percent = null;
    if (Number(challenge.goal_value) > 0) percent = Math.min(100, Math.round((myProgress / Number(challenge.goal_value)) * 100));
    res.json({ challenge, top: top.rows, myProgress, percent });
  } catch (e) {
    console.error('challenge summary failed', e);
    res.status(500).json({ error: 'summary_failed' });
  } finally {
    client.release();
  }
});
/* END B3_PATCH_MARKER */


const PORT = process.env.PORT || 4000;
app.listen(PORT, ()=> console.log('Server running on port', PORT));


// === Social endpoints: likes, comments, follows, notifications ===

// Toggle like
app.post('/api/posts/:id/like', requireAuth(pool), async (req, res) => {
  const postId = req.params.id;
  const userId = req.user.id;
  const client = await pool.connect();
  try {
    // check if exists
    const exists = await client.query('SELECT id FROM likes WHERE post_id=$1 AND user_id=$2', [postId, userId]);
    if (exists.rowCount > 0) {
      await client.query('DELETE FROM likes WHERE post_id=$1 AND user_id=$2', [postId, userId]);
      // decrement likes_count on posts
      await client.query('UPDATE posts SET likes_count = GREATEST(coalesce(likes_count,0)-1,0) WHERE id=$1', [postId]);
      return res.json({ liked: false });
    }
    const lid = uuidv4();
    await client.query('INSERT INTO likes (id, post_id, user_id) VALUES ($1,$2,$3)', [lid, postId, userId]);
    await client.query('UPDATE posts SET likes_count = coalesce(likes_count,0)+1 WHERE id=$1', [postId]);
    // create notification for post author
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

// Post a comment
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
    // create notification for post author
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

// Get comments for a post
app.get('/api/posts/:id/comments', async (req, res) => {
  const postId = req.params.id;
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT c.id, c.text, c.created_at, u.id as user_id, u.username, u.display_name FROM comments c JOIN users u ON u.id = c.user_id WHERE c.post_id = $1 ORDER BY c.created_at ASC`, [postId]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'comments_fetch_failed' }); } finally { client.release(); }
});

// Follow a user
app.post('/api/users/:id/follow', requireAuth(pool), async (req, res) => {
  const target = req.params.id;
  const me = req.user.id;
  if (me === target) return res.status(400).json({ error: 'cannot_follow_self' });
  const client = await pool.connect();
  try {
    await client.query('INSERT INTO follows (id, follower_id, followee_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [uuidv4(), me, target]);
    // create notification
    await client.query("INSERT INTO notifications (id,user_id,actor_id,verb,target_type,target_id,data) VALUES ($1,$2,$3,'follow','user',$4,$5)", [uuidv4(), target, me, target, JSON.stringify({})]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'follow_failed' }); } finally { client.release(); }
});

// Unfollow
app.post('/api/users/:id/unfollow', requireAuth(pool), async (req, res) => {
  const target = req.params.id;
  const me = req.user.id;
  const client = await pool.connect();
  try {
    await client.query('DELETE FROM follows WHERE follower_id=$1 AND followee_id=$2', [me, target]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'unfollow_failed' }); } finally { client.release(); }
});

// Get followers / following
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

// Get notifications for current user
app.get('/api/notifications', requireAuth(pool), async (req, res) => {
  const client = await pool.connect();
  try {
    const r = await client.query(`SELECT n.id, n.verb, n.target_type, n.target_id, n.data, n.is_read, n.created_at, a.id as actor_id, a.username, a.display_name FROM notifications n LEFT JOIN users a ON a.id = n.actor_id WHERE n.user_id = $1 ORDER BY n.created_at DESC LIMIT 100`, [req.user.id]);
    res.json(r.rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'notifications_failed' }); } finally { client.release(); }
});

// Mark notification read
app.post('/api/notifications/:id/read', requireAuth(pool), async (req, res) => {
  const id = req.params.id;
  const client = await pool.connect();
  try {
    await client.query('UPDATE notifications SET is_read = true WHERE id = $1', [id]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'mark_read_failed' }); } finally { client.release(); }
});

// === end social endpoints ===
