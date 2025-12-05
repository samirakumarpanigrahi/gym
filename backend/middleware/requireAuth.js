const auth = require('../server_auth_helpers/auth');

// returns middleware that sets req.user = { id: userId }
module.exports = function requireAuth(pool) {
  return async function (req, res, next) {
    const h = req.headers.authorization;
    if (!h || !h.startsWith('Bearer ')) return res.status(401).json({ error: 'no_token' });
    const token = h.slice('Bearer '.length);
    const payload = auth.verifyJwt(token);
    if (!payload || !payload.userId) return res.status(401).json({ error: 'invalid_token' });
    // load user from DB
    const client = await pool.connect();
    try {
      const r = await client.query('SELECT id, username, display_name, email FROM users WHERE id = $1', [payload.userId]);
      if (r.rowCount === 0) return res.status(401).json({ error: 'user_not_found' });
      req.user = r.rows[0];
      next();
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'auth_error' });
    } finally {
      client.release();
    }
  };
};
