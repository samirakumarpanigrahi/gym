#!/usr/bin/env bash
set -e
ROOT="$(pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"

echo "Applying B1 (Gyms & Local Discovery) patch to $ROOT"

# 1) Append sample gyms to seed file
SEED_FILE="$BACKEND/seeds/001_seed_demo.sql"
if [ ! -f "$SEED_FILE" ]; then
  echo "ERROR: seed file not found at $SEED_FILE"
  exit 1
fi

if ! grep -q "g1aaaaaaaa-1111" "$SEED_FILE"; then
  cat >> "$SEED_FILE" <<'SQL'

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
SQL
  echo "Appended sample gyms to seeds."
else
  echo "Sample gyms already present in seeds."
fi

# 2) Patch backend/server.js: insert gyms endpoints and update feed to support scope=local
SERVER="$BACKEND/server.js"
if [ ! -f "$SERVER" ]; then
  echo "ERROR: backend server.js not found at $SERVER"
  exit 1
fi

# create a temp copy
TMP="$(mktemp)"
cp "$SERVER" "$TMP"

# Insert gyms block before the public feed comment if available, else append
GYMS_BLOCK='// --- Gyms & local feed endpoints ---'
if ! grep -q "${GYMS_BLOCK}" "$SERVER"; then
  awk -v block="$GYMS_BLOCK" '
  BEGIN { printed=0 }
  {
    lines[NR]=$0
  }
  END {
    inserted=0
    for(i=1;i<=NR;i++){
      if(!inserted && lines[i] ~ /\/\/ Public feed \(simple\)/){
        print gensub(/.*/,"","g", "") # noop to ensure awk version compatibility
      }
    }
    # We'll simply append the block at end for safe insertion
    for(i=1;i<=NR;i++) print lines[i]
    print ""
    print block
    print ""
    print "app.get(\"/api/gyms/nearby\", async (req, res) => {"
    print "  const { lat, lng } = req.query;"
    print "  const client = await pool.connect();"
    print "  try {"
    print "    if (!lat || !lng) {"
    print "      const r = await client.query(\"SELECT id, name, lat, lon, address, photo_url FROM gyms LIMIT 50\");"
    print "      return res.json(r.rows);"
    print "    }"
    print "    const r = await client.query(\"SELECT id, name, lat, lon, address, photo_url, ((lat::double precision - $1::double precision)*(lat::double precision - $1::double precision) + (lon::double precision - $2::double precision)*(lon::double precision - $2::double precision)) as dist2 FROM gyms ORDER BY dist2 ASC LIMIT 50\", [parseFloat(lat), parseFloat(lng)]);"
    print "    res.json(r.rows.map(row => ({ id: row.id, name: row.name, lat: row.lat, lon: row.lon, address: row.address, photo_url: row.photo_url })));"
    print "  } catch (e) { console.error(e); res.status(500).json({ error: 'gyms_nearby_failed' }); } finally { client.release(); }"
    print "});"
    print ""
    print "app.get('/api/gyms/:id', async (req, res) => {"
    print "  const id = req.params.id;"
    print "  const client = await pool.connect();"
    print "  try {"
    print "    const r = await client.query('SELECT id, name, lat, lon, address, photo_url FROM gyms WHERE id = $1 LIMIT 1', [id]);"
    print "    if (r.rowCount === 0) return res.status(404).json({ error: \"not_found\" });"
    print "    res.json(r.rows[0]);"
    print "  } catch (e) { console.error(e); res.status(500).json({ error: 'gym_detail_failed' }); } finally { client.release(); }"
    print "});"
    print ""
    print "app.get('/api/gyms/:id/members', async (req, res) => {"
    print "  const id = req.params.id;"
    print "  const client = await pool.connect();"
    print "  try {"
    print "    const r = await client.query(\"SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u WHERE u.gym_id = $1 LIMIT 100\", [id]);"
    print "    res.json(r.rows);"
    print "  } catch (e) { console.error(e); res.status(500).json({ error: 'gym_members_failed' }); } finally { client.release(); }"
    print "});"
    print ""
    print "app.post('/api/gyms/:id/join', requireAuth(pool), async (req, res) => {"
    print "  const id = req.params.id;"
    print "  const userId = req.user.id;"
    print "  const client = await pool.connect();"
    print "  try {"
    print "    await client.query('UPDATE users SET gym_id = $1 WHERE id = $2', [id, userId]);"
    print "    res.json({ ok: true });"
    print "  } catch (e) { console.error(e); res.status(500).json({ error: 'join_gym_failed' }); } finally { client.release(); }"
    print "});"
  }' "$SERVER" > "$TMP"
  mv "$TMP" "$SERVER"
  echo "Appended gyms endpoints to $SERVER (appended near file end)."
else
  echo "Gyms endpoints already present in $SERVER"
fi

# 2b) Patch feed endpoint to handle ?scope=local
# We'll add a wrapper: if query scope=local and Authorization present, try to find user's gym and filter posts
# This is a textual patch: find the SELECT block that queries posts and replace with a scope-aware variant.
python3 - <<'PY'
import re,sys
server="$BACKEND/server.js"
with open(server,'r') as f:
    s=f.read()
if "WHERE p.visibility_status = 'visible'" in s and "scope = req.query.scope" not in s:
    new = s.replace(
        "WHERE p.visibility_status = 'visible'\n              ORDER BY p.created_at DESC\n              LIMIT 50\n            `);",
        "WHERE p.visibility_status = 'visible'\n              ORDER BY p.created_at DESC\n              LIMIT 50\n            `);"
    )
    # more robust: insert new logic near the first occurrence of the posts query
    target = \"SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title\\n              FROM posts p\\n              JOIN users u ON u.id = p.author_id\\n              LEFT JOIN workouts w ON w.id = p.linked_workout_id\\n              WHERE p.visibility_status = 'visible'\\n              ORDER BY p.created_at DESC\\n              LIMIT 50\\n            \"; 
    if target in s:
        parts = s.split(target)
        prefix = parts[0]
        suffix = ''.join(parts[1:])
        inject = '''const scope = req.query.scope || 'global';
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
            const r_local = await client.query(`SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title FROM posts p JOIN users u ON u.id = p.author_id LEFT JOIN workouts w ON w.id = p.linked_workout_id WHERE p.visibility_status = 'visible' AND u.gym_id = $1 ORDER BY p.created_at DESC LIMIT 50`, [userGym]);
            r = r_local;
          } else {
            r = await client.query(`SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title FROM posts p JOIN users u ON u.id = p.author_id LEFT JOIN workouts w ON w.id = p.linked_workout_id WHERE p.visibility_status = 'visible' ORDER BY p.created_at DESC LIMIT 50`);
          }
        } else {
          r = await client.query(`SELECT p.id, p.caption, p.created_at, u.id as author_id, u.username, u.display_name, w.id as workout_id, w.title as workout_title FROM posts p JOIN users u ON u.id = p.author_id LEFT JOIN workouts w ON w.id = p.linked_workout_id WHERE p.visibility_status = 'visible' ORDER BY p.created_at DESC LIMIT 50`);
        }
        '''
        new_s = prefix + inject + suffix
        with open(server,'w') as f:
            f.write(new_s)
        print("Patched feed handler for local scope.")
    else:
        print("Could not find posts query block; skipping automatic patch (you can patch manually).")
else:
    print("Feed already patched or posts block not present.")
PY

echo "Backend patched. Please open backend/server.js and review the inserted code (safety)."

# 3) Frontend: add API helpers for gyms (services/api.js)
API="$FRONTEND/services/api.js"
if [ ! -f "$API" ]; then
  echo "ERROR: frontend API file not found at $API"
  exit 1
fi

if ! grep -q "apiGetGymsNearby" "$API"; then
  cat >> "$API" <<'JS'

export async function apiGetGymsNearby(lat, lng) {
  const q = lat && lng ? `?lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lng)}` : '';
  return request(`/api/gyms/nearby${q}`);
}

export async function apiGetGym(id) {
  return request(`/api/gyms/${id}`);
}

export async function apiGetGymMembers(id) {
  return request(`/api/gyms/${id}/members`);
}

export async function apiJoinGym(id) {
  return request(`/api/gyms/${id}/join`, { method: 'POST' });
}
JS
  echo "Appended gym API helpers to $API"
else
  echo "Gym API helpers already exist in $API"
fi

# 4) Frontend: add screens (GymDiscoveryScreen, GymDetailScreen)
mkdir -p "$FRONTEND/screens"

GYM_DISC="$FRONTEND/screens/GymDiscoveryScreen.js"
if [ ! -f "$GYM_DISC" ]; then
  cat > "$GYM_DISC" <<'JS'
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
  echo "Created $GYM_DISC"
else
  echo "$GYM_DISC already exists"
fi

GYM_DETAIL="$FRONTEND/screens/GymDetailScreen.js"
if [ ! -f "$GYM_DETAIL" ]; then
  cat > "$GYM_DETAIL" <<'JS'
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
      <Toast />
    </View>
  );
}
JS
  echo "Created $GYM_DETAIL"
else
  echo "$GYM_DETAIL already exists"
fi

# 5) Update frontend App.js to register routes if not already added
APP="$FRONTEND/App.js"
if [ -f "$APP" ]; then
  if ! grep -q "GymDiscoveryScreen" "$APP"; then
    # insert import lines after NotificationsScreen import
    perl -0777 -pe "s/import NotificationsScreen from '\\.\\/screens\\/NotificationsScreen';/import NotificationsScreen from '\\.\\/screens\\/NotificationsScreen';\\nimport GymDiscoveryScreen from '\\.\\/screens\\/GymDiscoveryScreen';\\nimport GymDetailScreen from '\\.\\/screens\\/GymDetailScreen';/s" -i "$APP"
    # add routes (search for Notifications route and append)
    perl -0777 -pe "s/<Stack.Screen name=\\\"Notifications\\\" component=\\{NotificationsScreen\\} options=\\{\\{title: 'Notifications'\\}\\} \\/>/<Stack.Screen name=\\\"Notifications\\\" component=\\{NotificationsScreen\\} options=\\{\\{title: 'Notifications'\\}\\} \\/>\\n          <Stack.Screen name=\\\"GymDiscovery\\\" component=\\{GymDiscoveryScreen\\} options=\\{\\{title: 'Find Gyms'\\}\\} \\/>\\n          <Stack.Screen name=\\\"GymDetail\\\" component=\\{GymDetailScreen\\} options=\\{\\{title: 'Gym'\\}\\} \\/>/s" -i "$APP"
    echo "Updated $APP to include gym screens."
  else
    echo "App.js already contains Gym screens."
  fi
else
  echo "Warning: frontend App.js not found at $APP"
fi

# 6) Update FeedScreen UI to include local/global toggle + link to Gym discovery
FEED="$FRONTEND/screens/FeedScreen.js"
if [ -f "$FEED" ]; then
  if ! grep -q "Find Gyms" "$FEED"; then
    # insert feedScope state and modify load call
    perl -0777 -pe "s/const load = async ()=>{ try { const data = await apiFetchFeed\\(\\); setPosts\\(data\\); } catch\\(e\\)\\{ console.error\\(e\\); \\} };/const [feedScope, setFeedScope] = React.useState('global');\\n    const load = async ()=>{ try { const data = await apiFetchFeed\\(feedScope === 'local' \\? '?scope=local' : ''\\); setPosts\\(data\\); } catch\\(e\\)\\{ console.error\\(e\\); \\} };/s" -i "$FEED"
    # add buttons to header area
    perl -0777 -pe "s/<View style=\\{\\{padding:12\\}\\}>/<View style=\\{\\{padding:12\\}\\}>\\n            <View style=\\{\\{flexDirection:'row', marginBottom:8\\}\\}>\\n              <Button title=\\\"Global\\\" onPress=\\{\\(\\) => \\{ setFeedScope\\('global'\\); load\\(\\); \\} \\} \\/>\\n              <View style=\\{\\{width:8\\}\\} \\/>\\n              <Button title=\\\"Local\\\" onPress=\\{\\(\\) => \\{ setFeedScope\\('local'\\); load\\(\\); \\} \\} \\/>\\n              <View style=\\{\\{width:8\\}\\} \\/>\\n              <Button title=\\\"Find Gyms\\\" onPress=\\{\\(\\) => navigation.navigate\\('GymDiscovery'\\) \\} \\/>\\n            <\\/View>/s" -i "$FEED"
    echo "Patched $FEED with Local/Global toggle and Find Gyms button."
  else
    echo "FeedScreen appears to already have the Find Gyms button."
  fi
else
  echo "Warning: FeedScreen not found at $FEED"
fi

echo "B1 patch applied. Please review changes, run 'npm install' in frontend/backend if you added libs, then run backend & frontend as usual."
echo ""
echo "Run these commands to test:"
echo "  # backend migrations (if using local DB)"
echo "  psql \$DATABASE_URL -f backend/migrations/001_create_schema.sql"
echo "  psql \$DATABASE_URL -f backend/migrations/002_refresh_tokens.sql"
echo "  psql \$DATABASE_URL -f backend/migrations/003_social.sql || true"
echo "  psql \$DATABASE_URL -f backend/seeds/001_seed_demo.sql"
echo ""
echo "Start backend: cd backend && npm install && npm start"
echo "Start frontend: cd frontend && npm install && expo start"
