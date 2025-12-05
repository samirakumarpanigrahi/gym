import AsyncStorage from '@react-native-async-storage/async-storage';

const API_BASE = process.env.API_BASE || 'http://10.0.2.2:4000'; // use 10.0.2.2 for Android emulator to reach localhost; replace with your server URL

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
  // limit retries per request using x-retry-count header
  const prevCount = parseInt(options.headers['x-retry-count'] || '0', 10);
  options.headers['x-retry-count'] = String(prevCount);

  const token = await getToken();
  const headers = options.headers || {};
  headers['Content-Type'] = headers['Content-Type'] || 'application/json';
  if (token) headers['Authorization'] = 'Bearer ' + token;
  const res = await fetch(API_BASE + path, { ...options, headers });
  if (res.status === 401 && retry) {
  // check retry count limit
  const currentRetries = parseInt(options.headers['x-retry-count'] || '0', 10);
  if (currentRetries >= 1) {
    // already retried once - clear tokens and throw
    await AsyncStorage.removeItem('auth_token');
    await AsyncStorage.removeItem('refresh_token');
    const txt = await res.text();
    let err = txt; try { err = JSON.parse(txt); } catch(e) {}
    throw err;
  }

    // try refreshing
    const refreshToken = await getRefreshToken();
    if (refreshToken) {
      try {
        const r = await fetch(API_BASE + '/api/auth/refresh', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ refreshToken }) });
        if (r.ok) {
          const data = await r.json();
          if (data.token) {
            await AsyncStorage.setItem('auth_token', data.token);
            // retry original request once
            return request(path, options, false);
          }
        } else {
          // failed to refresh - clear tokens
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
  // if no content
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
  // call logout endpoint to revoke refresh token; ignore errors
  try {
    await request('/api/auth/logout', { method: 'POST', body: JSON.stringify({ refreshToken }) }, false);
  } catch (e) {
    console.warn('logout request failed', e);
  }
  await AsyncStorage.removeItem('auth_token');
  await setRefreshToken(null);
}

export async function apiFetchFeed() {
  return request('/api/feed');
}

export async function apiCreateWorkout(payload) {
  return request('/api/workouts', { method: 'POST', body: JSON.stringify(payload) });
}

export async function apiPublishWorkout(workoutId, caption) {
  return request(`/api/workouts/${workoutId}/publish`, { method: 'POST', body: JSON.stringify({ caption }) });
}

export async function saveToken(token) {
  await AsyncStorage.setItem('auth_token', token);
}

export async function clearToken() {
  await AsyncStorage.removeItem('auth_token');
}


export async function apiUploadFile(uri) {
  // uploads a local file (uri) as multipart/form-data under field 'file'
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


export async function apiToggleLike(postId) {
  return request(`/api/posts/${postId}/like`, { method: 'POST' });
}

export async function apiPostComment(postId, text) {
  return request(`/api/posts/${postId}/comments`, { method: 'POST', body: JSON.stringify({ text }) });
}

export async function apiGetComments(postId) {
  return request(`/api/posts/${postId}/comments`);
}

export async function apiFollow(userId) {
  return request(`/api/users/${userId}/follow`, { method: 'POST' });
}
export async function apiUnfollow(userId) {
  return request(`/api/users/${userId}/unfollow`, { method: 'POST' });
}

export async function apiGetNotifications() {
  return request('/api/notifications');
}
export async function apiMarkNotificationRead(id) {
  return request(`/api/notifications/${id}/read`, { method: 'POST' });
}
export function apiGetChallengeSummary(id){ return request(`/api/challenges/${id}/summary`); }
export function apiPublishWorkoutWithMetrics(id, caption){ return request(`/api/workouts/${id}/publish-metrics`, { method: 'POST', body: JSON.stringify({ caption }) }); }
export function apiGetChallengeWorkouts(id){ return request(`/api/challenges/${id}/workouts`); }