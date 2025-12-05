-- migrations/004_challenges.sql
-- Challenges + challenge_participants

CREATE TABLE IF NOT EXISTS challenges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  creator_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  gym_id UUID REFERENCES gyms(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  start_date TIMESTAMP WITH TIME ZONE NOT NULL,
  end_date TIMESTAMP WITH TIME ZONE NOT NULL,
  goal_type TEXT NOT NULL, -- 'workouts_count' | 'weight_lifted' | 'distance'
  goal_value NUMERIC NOT NULL DEFAULT 0,
  visibility TEXT DEFAULT 'public', -- 'gym' or 'public'
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

CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge_id ON challenge_participants(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenges_gym_id ON challenges(gym_id);
