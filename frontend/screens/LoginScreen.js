import React, { useState, useContext } from 'react';
import { View, TextInput, Button, Text, Alert } from 'react-native';
import { AuthContext } from '../services/AuthContext';

export default function LoginScreen({ navigation }) {
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const { signIn } = useContext(AuthContext);

  async function onLogin() {
    try {
      await signIn({ username: username || undefined, email: email || undefined, password });
    } catch (e) {
      Alert.alert('Login failed', JSON.stringify(e));
    }
  }

  return (
    <View style={{padding:12}}>
      <Text>Username or Email</Text>
      <TextInput value={username} onChangeText={setUsername} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:8}} />
      <Text>Password</Text>
      <TextInput secureTextEntry value={password} onChangeText={setPassword} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:12}} />
      <Button title="Login" onPress={onLogin} />
      <View style={{height:12}} />
      <Button title="Register" onPress={()=>navigation.navigate('Register')} />
    </View>
  );
}
