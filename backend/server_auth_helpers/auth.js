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
  // payload should include { userId }
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
  // generate a random token string (uuid)
  return uuidv4();
}

module.exports = { hashPassword, comparePassword, generateAccessToken, verifyJwt, generateRefreshToken };
