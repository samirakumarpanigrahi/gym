import React, { useState, useContext } from 'react';
import { View, TextInput, Button, Text, Alert } from 'react-native';
import { AuthContext } from '../services/AuthContext';

export default function RegisterScreen({ navigation }) {
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const { signUp } = useContext(AuthContext);

  async function onRegister() {
    try {
      await signUp({ username, email, password, display_name: displayName });
    } catch (e) {
      Alert.alert('Register failed', JSON.stringify(e));
    }
  }

  return (
    <View style={{padding:12}}>
      <Text>Username</Text>
      <TextInput value={username} onChangeText={setUsername} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} />
      <Text>Display name</Text>
      <TextInput value={displayName} onChangeText={setDisplayName} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} />
      <Text>Email</Text>
      <TextInput value={email} onChangeText={setEmail} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} />
      <Text>Password</Text>
      <TextInput secureTextEntry value={password} onChangeText={setPassword} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:12}} />
      <Button title="Register" onPress={onRegister} />
    </View>
  );
}
