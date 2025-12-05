import React, { useContext } from 'react';
import { View, Text, Button, Alert } from 'react-native';
import { AuthContext } from '../services/AuthContext';

export default function ProfileScreen({ navigation }) {
  const { user, signOut } = useContext(AuthContext);

  async function onLogout() {
    try {
      await signOut();
    } catch (e) {
      Alert.alert('Logout failed', JSON.stringify(e));
    }
  }

  return (
    <View style={{padding:12}}>
      <Text>Username: {user?.username}</Text>
      <Text>Display Name: {user?.display_name || user?.displayName}</Text>
      <Text>Email: {user?.email}</Text>
      <View style={{height:12}} />
      <Button title="Logout" onPress={onLogout} />
    </View>
  );
}
