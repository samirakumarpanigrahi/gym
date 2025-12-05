-- seeds/001_seed_demo.sql

INSERT INTO gyms (id, name, lat, lon, address)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  'Iron Temple Gym',
  28.6139, 77.2090,
  'Connaught Place, New Delhi, India'
);

INSERT INTO users (id, username, display_name, email, password_hash, is_trainer, gym_id, level, bio)
VALUES (
  '22222222-2222-2222-2222-222222222222',
  'demo_user',
  'Demo User',
  'demo@example.com',
  -- password is 'demo1234' hashed with bcryptjs; for initial demo you can re-register or set your own password
  '$2a$10$u1Q9nq8z1sF6o8rjYq5hseYc5b3nWj1X6fGk6a1Qx2c3d4e5f6g7',
  false,
  '11111111-1111-1111-1111-111111111111',
  'intermediate',
  'Demo account for the Expo starter'
);

INSERT INTO workouts (id, user_id, title, date, privacy, total_volume, duration_seconds, notes)
VALUES (
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222',
  'Leg Day — Demo',
  now() - interval '1 day',
  'public',
  0,
  1800,
  'Demo workout for the starter app'
);

INSERT INTO workout_exercises (id, workout_id, exercise_name, primary_muscle, "order")
VALUES
  ('44444444-4444-4444-4444-444444444444','33333333-3333-3333-3333-333333333333','Back Squat','Quadriceps',0),
  ('55555555-5555-5555-5555-555555555555','33333333-3333-3333-3333-333333333333','Romanian Deadlift','Hamstrings',1);

INSERT INTO sets (id, workout_exercise_id, set_no, reps, weight, rpe, rest_seconds)
VALUES
  ('66666666-6666-6666-6666-666666666666','44444444-4444-4444-4444-444444444444',1,5,80,7,120),
  ('77777777-7777-7777-7777-777777777777','44444444-4444-4444-4444-444444444444',2,5,80,7,120),
  ('88888888-8888-8888-8888-888888888888','55555555-5555-5555-5555-555555555555',1,8,60,7,90),
  ('99999999-9999-9999-9999-999999999999','55555555-5555-5555-5555-555555555555',2,8,60,7,90);

UPDATE workouts w
SET total_volume = COALESCE((
  SELECT SUM(s.reps * s.weight)
  FROM workout_exercises we
  JOIN sets s ON s.workout_exercise_id = we.id
  WHERE we.workout_id = w.id
),0)
WHERE w.id = '33333333-3333-3333-3333-333333333333';

INSERT INTO posts (id, author_id, type, linked_workout_id, caption, visibility_status, likes_count, comments_count)
VALUES (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '22222222-2222-2222-2222-222222222222',
  'workout',
  '33333333-3333-3333-3333-333333333333',
  'Demo leg day — felt strong! #PR?',
  'visible',
  0,
  0
);


-- demo follow, like, comment
INSERT INTO follows (id, follower_id, followee_id) VALUES ('f1111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','22222222-2222-2222-2222-222222222222') ON CONFLICT DO NOTHING;
-- create a second demo user to follow/like
INSERT INTO users (id, username, display_name, email, password_hash, is_trainer, gym_id, level, bio) VALUES ('33333333-3333-3333-3333-333333333333','demo_user2','Demo User2','demo2@example.com','$2a$10$u1Q9nq8z1sF6o8rjYq5hseYc5b3nWj1X6fGk6a1Qx2c3d4e5f6g7',false,'11111111-1111-1111-1111-111111111111','beginner','Second demo user') ON CONFLICT DO NOTHING;
-- demo like by demo_user2 on the demo post
INSERT INTO likes (id, post_id, user_id) VALUES ('l1111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','33333333-3333-3333-3333-333333333333') ON CONFLICT DO NOTHING;
-- demo comment
INSERT INTO comments (id, post_id, user_id, text) VALUES ('c1111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','33333333-3333-3333-3333-333333333333','Nice work!') ON CONFLICT DO NOTHING;
-- notification for post author
INSERT INTO notifications (id, user_id, actor_id, verb, target_type, target_id, data) VALUES ('n1111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333','comment','post','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '{"text":"Nice work!"}') ON CONFLICT DO NOTHING;

-- sample gyms for discovery
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

-- sample challenge for demo (workouts_count)
INSERT INTO challenges (id, creator_user_id, gym_id, title, description, start_date, end_date, goal_type, goal_value, visibility)
VALUES ('sample_challenge_1','22222222-2222-2222-2222-222222222222','g1aaaaaaaa-1111-1111-1111-111111111111',
 '7-day Push Challenge','Do at least 1 logged workout per day for 7 days', now(), now() + interval '7 days', 'workouts_count', 7, 'gym')
ON CONFLICT DO NOTHING;
