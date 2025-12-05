import React, { createContext, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { apiLogin, apiRegister, saveToken, clearToken, apiLogout } from './api';

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
      await saveToken(res.token);
      await AsyncStorage.setItem('auth_user', JSON.stringify(res.user));
      setUser(res.user);
      return res.user;
    }
    throw new Error('Login failed');
  }

  async function signUp({ username, email, password, display_name }) {
    const res = await apiRegister({ username, email, password, display_name });
    if (res && res.token) {
      await saveToken(res.token);
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
    await clearToken();
    await AsyncStorage.removeItem('auth_user');
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, loading, signIn, signUp, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}
