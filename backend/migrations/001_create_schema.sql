-- migrations/001_create_schema.sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE gyms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  address TEXT,
  photo_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username TEXT NOT NULL UNIQUE,
  display_name TEXT,
  email TEXT UNIQUE,
  password_hash TEXT NOT NULL,
  avatar_url TEXT,
  is_trainer BOOLEAN DEFAULT false,
  gym_id UUID REFERENCES gyms(id),
  level TEXT,
  bio TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE workouts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT,
  date TIMESTAMP WITH TIME ZONE,
  privacy TEXT DEFAULT 'private',
  total_volume BIGINT DEFAULT 0,
  duration_seconds INTEGER,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE workout_exercises (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_id UUID REFERENCES workouts(id) ON DELETE CASCADE,
  exercise_name TEXT NOT NULL,
  primary_muscle TEXT,
  "order" INTEGER DEFAULT 0
);

CREATE TABLE sets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_exercise_id UUID REFERENCES workout_exercises(id) ON DELETE CASCADE,
  set_no INTEGER,
  reps INTEGER,
  weight NUMERIC,
  rpe NUMERIC,
  rest_seconds INTEGER
);

CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type TEXT,
  linked_workout_id UUID REFERENCES workouts(id) ON DELETE SET NULL,
  caption TEXT,
  visibility_status TEXT DEFAULT 'visible',
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_workouts_user_id ON workouts(user_id);
