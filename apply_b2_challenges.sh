#!/usr/bin/env bash
set -e
ROOT="$(pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"

echo "Applying B2 (Challenges System) patch to $ROOT"

# Safety checks
if [ ! -d "$BACKEND" ] || [ ! -d "$FRONTEND" ]; then
  echo "ERROR: Could not find backend/ and frontend/ directories in $ROOT"
  exit 1
fi

# 1) Create migration file migrations/004_challenges.sql
MIG="$BACKEND/migrations/004_challenges.sql"
if [ -f "$MIG" ]; then
  echo "Migration $MIG already exists — skipping creation."
else
  cat > "$MIG" <<'SQL'
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
SQL
  echo "Created migration $MIG"
fi

# 2) Append sample challenge to seeds (if not already present)
SEED="$BACKEND/seeds/001_seed_demo.sql"
if grep -q "sample_challenge_1" "$SEED"; then
  echo "Sample challenge already present in seeds — skipping."
else
  cat >> "$SEED" <<'SQL'

-- sample challenge for demo (workouts_count)
INSERT INTO challenges (id, creator_user_id, gym_id, title, description, start_date, end_date, goal_type, goal_value, visibility)
VALUES ('sample_challenge_1','22222222-2222-2222-2222-222222222222','g1aaaaaaaa-1111-1111-1111-111111111111',
 '7-day Push Challenge','Do at least 1 logged workout per day for 7 days', now(), now() + interval '7 days', 'workouts_count', 7, 'gym')
ON CONFLICT DO NOTHING;
SQL
  echo "Appended sample challenge to $SEED"
fi

# 3) Backend: patch server.js to add challenge endpoints and update publish flow
SERVER="$BACKEND/server.js"
if [ ! -f "$SERVER" ]; then
  echo "ERROR: backend/server.js not found at $SERVER"
  exit 1
fi

# Add endpoints block if not present
if grep -q "=== Challenges endpoints ===" "$SERVER"; then
  echo "Challenges endpoints appear already present in server.js — skipping patch."
else
  # We'll append endpoints near the end (before app.listen) to keep it simple
  awk 'BEGIN{p=1} { if($0 ~ /app.listen\\(/) {print "/* ==== Challenges endpoints inserted by patch ==== */\n"; print "const { v4: uuidv4 } = require(\"uuid\");\n"; print "/* Create challenge */\napp.post(\\\"/api/challenges\\\", requireAuth(pool), async (req,res)=>{ (async()=>{ const client=await pool.connect(); try{ const {title,description,start_date,end_date,goal_type,goal_value,gym_id,visibility} = req.body; if(!title||!start_date||!end_date||!goal_type) return res.status(400).json({ error: \\\"missing_fields\\\" }); const cid = uuidv4(); await client.query(`INSERT INTO challenges (id, creator_user_id, gym_id, title, description, start_date, end_date, goal_type, goal_value, visibility) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [cid, req.user.id, gym_id || null, title, description || null, start_date, end_date, goal_type, goal_value || 0, visibility || 'public']); res.json({ id: cid }); }catch(e){ console.error(e); res.status(500).json({ error: \\\"create_challenge_failed\\\" }); } finally{ client.release(); } })(); });\n"; print "/* Join challenge */\napp.post(\\\"/api/challenges/:id/join\\\", requireAuth(pool), async (req,res)=>{ (async()=>{ const client=await pool.connect(); try{ const cid=req.params.id; await client.query('INSERT INTO challenge_participants (id, challenge_id, user_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [uuidv4(), cid, req.user.id]); res.json({ ok:true }); }catch(e){ console.error(e); res.status(500).json({ error: \\\"join_failed\\\" }); } finally{ client.release(); } })(); });\n"; print "/* Get public challenges */\napp.get(\\\"/api/challenges/public\\\", async (req,res)=>{ (async()=>{ const client=await pool.connect(); try{ const r = await client.query('SELECT * FROM challenges WHERE visibility = \\\"public\\\" ORDER BY start_date DESC LIMIT 100'); res.json(r.rows); }catch(e){ console.error(e); res.status(500).json({ error: \\\"challenges_list_failed\\\" }); } finally{ client.release(); } })(); });\n"; print "/* Get gym challenges */\napp.get(\\\"/api/challenges/gym/:id\\\", async (req,res)=>{ (async()=>{ const client=await pool.connect(); try{ const r = await client.query('SELECT * FROM challenges WHERE gym_id = $1 ORDER BY start_date DESC LIMIT 100', [req.params.id]); res.json(r.rows); }catch(e){ console.error(e); res.status(500).json({ error: \\\"challenges_gym_failed\\\" }); } finally{ client.release(); } })(); });\n"; print "/* Get challenge detail */\napp.get(\\\"/api/challenges/:id\\\", async (req,res)=>{ (async()=>{ const client=await pool.connect(); try{ const r = await client.query('SELECT * FROM challenges WHERE id = $1 LIMIT 1', [req.params.id]); if(r.rowCount===0) return res.status(404).json({ error:\\\"not_found\\\"}); const c = r.rows[0]; const p = await client.query('SELECT count(*) as participants FROM challenge_participants WHERE challenge_id = $1',[req.params.id]); c.participants = parseInt(p.rows[0].participants,10)||0; res.json(c); }catch(e){ console.error(e); res.status(500).json({ error: \\\"challenge_detail_failed\\\" }); } finally{ client.release(); } })(); });\n"; print "/* Leaderboard: simple ordering by progress_value desc */\napp.get(\\\"/api/challenges/:id/leaderboard\\\", async (req,res)=>{ (async()=>{ const client=await pool.connect(); try{ const r = await client.query('SELECT cp.user_id, cp.progress_value, u.username, u.display_name, u.avatar_url FROM challenge_participants cp JOIN users u ON u.id = cp.user_id WHERE cp.challenge_id = $1 ORDER BY cp.progress_value DESC LIMIT 100', [req.params.id]); res.json(r.rows); }catch(e){ console.error(e); res.status(500).json({ error: \\\"leaderboard_failed\\\" }); } finally{ client.release(); } })(); });\n"; print "/* On publish workout: increment workout-count progress for joined challenges that are active and of type 'workouts_count' */\n"; print "/* We patch the existing publish endpoint earlier in file. If not possible, consider adding challenge progress updater as a separate endpoint and call it from the client when publishing. */\n"; } print $0 }' "$SERVER" > "$SERVER.patched" && mv "$SERVER.patched" "$SERVER"
  echo "Appended challenge endpoints to $SERVER (appended before app.listen)."
fi

# Note: the awk insertion above appends endpoints; you should review backend/server.js to ensure no duplicate imports and that uuid/v4 is available.

# 4) Frontend: add API helpers to frontend/services/api.js
API="$FRONTEND/services/api.js"
if ! grep -q "apiCreateChallenge" "$API"; then
  cat >> "$API" <<'JS'

export async function apiCreateChallenge(payload) {
  return request('/api/challenges', { method: 'POST', body: JSON.stringify(payload) });
}

export async function apiJoinChallenge(id) {
  return request(`/api/challenges/${id}/join`, { method: 'POST' });
}

export async function apiListPublicChallenges() {
  return request('/api/challenges/public');
}

export async function apiListGymChallenges(gymId) {
  return request(`/api/challenges/gym/${gymId}`);
}

export async function apiGetChallenge(id) {
  return request(`/api/challenges/${id}`);
}

export async function apiGetChallengeLeaderboard(id) {
  return request(`/api/challenges/${id}/leaderboard`);
}
JS
  echo "Appended challenge API helpers to $API"
else
  echo "Challenge API helpers already present in $API"
fi

# 5) Frontend: add screens
mkdir -p "$FRONTEND/screens"

# ChallengeListScreen
CLS="$FRONTEND/screens/ChallengeListScreen.js"
if [ ! -f "$CLS" ]; then
  cat > "$CLS" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, Button } from 'react-native';
import { apiListPublicChallenges, apiListGymChallenges } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ChallengeListScreen({ navigation }) {
  const [publicChallenges, setPublicChallenges] = useState([]);
  const [gymChallenges, setGymChallenges] = useState([]);

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
      <Toast />
    </View>
  );
}
JS
  echo "Created $CLS"
else
  echo "$CLS already exists"
fi

# ChallengeCreateScreen
CCS="$FRONTEND/screens/ChallengeCreateScreen.js"
if [ ! -f "$CCS" ]; then
  cat > "$CCS" <<'JS'
import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
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
      <Toast />
    </View>
  );
}
JS
  echo "Created $CCS"
else
  echo "$CCS already exists"
fi

# ChallengeDetailScreen
CDS="$FRONTEND/screens/ChallengeDetailScreen.js"
if [ ! -f "$CDS" ]; then
  cat > "$CDS" <<'JS'
import React, { useEffect, useState } from 'react';
import { View, Text, Button } from 'react-native';
import { apiGetChallenge, apiJoinChallenge, apiGetChallengeLeaderboard } from '../services/api';
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
      <Toast />
    </View>
  );
}
JS
  echo "Created $CDS"
else
  echo "$CDS already exists"
fi

# Leaderboard screen
LDS="$FRONTEND/screens/ChallengeLeaderboardScreen.js"
if [ ! -f "$LDS" ]; then
  cat > "$LDS" <<'JS'
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
      <Toast />
    </View>
  );
}
JS
  echo "Created $LDS"
else
  echo "$LDS already exists"
fi

# 6) Register screens in frontend/App.js (basic text replacement; review after)
APP="$FRONTEND/App.js"
if [ -f "$APP" ]; then
  if ! grep -q "ChallengeListScreen" "$APP"; then
    perl -0777 -pe "s/import GymDetailScreen from '\\.\\/screens\\/GymDetailScreen';/import GymDetailScreen from '\\.\\/screens\\/GymDetailScreen';\nimport ChallengeListScreen from '\\.\\/screens\\/ChallengeListScreen';\nimport ChallengeCreateScreen from '\\.\\/screens\\/ChallengeCreateScreen';\nimport ChallengeDetailScreen from '\\.\\/screens\\/ChallengeDetailScreen';\nimport ChallengeLeaderboardScreen from '\\.\\/screens\\/ChallengeLeaderboardScreen';/s" -i "$APP"
    perl -0777 -pe "s/<Stack.Screen name=\\\"GymDetail\\\" component=\\{GymDetailScreen\\} options=\\{\\{title: 'Gym'\\}\\} \\/>/<Stack.Screen name=\\\"GymDetail\\\" component=\\{GymDetailScreen\\} options=\\{\\{title: 'Gym'\\}\\} \\/>\n          <Stack.Screen name=\\\"Challenges\\\" component=\\{ChallengeListScreen\\} options=\\{\\{title: 'Challenges'\\}\\} \\/>\n          <Stack.Screen name=\\\"ChallengeCreate\\\" component=\\{ChallengeCreateScreen\\} options=\\{\\{title: 'Create Challenge'\\}\\} \\/>\n          <Stack.Screen name=\\\"ChallengeDetail\\\" component=\\{ChallengeDetailScreen\\} options=\\{\\{title: 'Challenge'\\}\\} \\/>\n          <Stack.Screen name=\\\"ChallengeLeaderboard\\\" component=\\{ChallengeLeaderboardScreen\\} options=\\{\\{title: 'Leaderboard'\\}\\} \\/>/s" -i "$APP"
    echo "Registered challenge screens in $APP (please review)."
  else
    echo "Challenge screens already registered in App.js"
  fi
else
  echo "Warning: App.js not found at $APP — please register screens manually."
fi

echo "B2 patch applied. IMPORTANT: review backend/server.js to ensure the endpoints added by the script are placed correctly and there are no duplicate variable imports. Start server and test the challenge endpoints."

echo ""
echo "Manual steps to integrate publish->challenge progress:"
echo " - The script added challenge endpoints. To update challenge progress automatically when publishing a workout,"
echo "   ensure backend /api/workouts/:id/publish updates challenge_participants for relevant challenges (workouts_count)."
echo " - If you want, I can provide a follow-up patch to insert that logic exactly into your publish endpoint once you confirm file layout."

echo ""
echo "After reviewing, run migrations and seed (see top of message)."
