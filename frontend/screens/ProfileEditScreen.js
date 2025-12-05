import React, { useState, useEffect, useContext } from 'react';
import { View, Text, TextInput, Button, Image, Alert } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { AuthContext } from '../services/AuthContext';
import { apiFetchFeed } from '../services/api';
import { apiLogout } from '../services/api';
import { apiRegister, apiLogin } from '../services/api';
import { apiCreateWorkout, apiPublishWorkout } from '../services/api';
import { apiFetchUser, apiUploadFile, apiUpdateProfile } from '../services/api';
import Toast from 'react-native-toast-message';

export default function ProfileEditScreen({ navigation }) {
  const { user, signOut } = useContext(AuthContext);
  const [displayName, setDisplayName] = useState(user?.display_name || user?.displayName || '');
  const [avatar, setAvatar] = useState(user?.avatar_url || null);
  const [uploading, setUploading] = useState(false);

  useEffect(()=>{ navigation.setOptions({ title: 'Edit Profile' }); }, []);

  async function pickImage() {
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      Alert.alert('Permission required', 'Allow access to photos to upload an avatar');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({ base64: false, quality: 0.7, allowsEditing: true });
    if (result.cancelled) return;
    // upload to backend
    try {
      setUploading(true);
      const uploadRes = await apiUploadFile(result.uri);
      setAvatar(uploadRes.url);
      Toast.show({ type: 'success', text1: 'Uploaded avatar' });
    } catch (e) {
      console.error(e);
      Toast.show({ type: 'error', text1: 'Upload failed', text2: JSON.stringify(e) });
    } finally { setUploading(false); }
  }

  async function saveProfile() {
    try {
      const updated = await apiUpdateProfile({ display_name: displayName, avatar_url: avatar });
      Toast.show({ type: 'success', text1: 'Profile updated' });
      // update local stored user
      // simple approach: sign out then rely on API to reflect changes on next login, or update AsyncStorage directly
      navigation.goBack();
    } catch (e) {
      console.error(e);
      Toast.show({ type: 'error', text1: 'Update failed', text2: JSON.stringify(e) });
    }
  }

  return (
    <View style={{padding:12}}>
      {avatar ? <Image source={{ uri: avatar }} style={{ width: 120, height: 120, borderRadius: 60, marginBottom:12 }} /> : <View style={{ width:120, height:120, backgroundColor:'#eee', marginBottom:12 }} /> }
      <Button title={avatar ? 'Change Avatar' : 'Upload Avatar'} onPress={pickImage} disabled={uploading} />
      <View style={{height:12}} />
      <Text>Display name</Text>
      <TextInput value={displayName} onChangeText={setDisplayName} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:12}} />
      <Button title="Save" onPress={saveProfile} />
      <View style={{height:12}} />
      <Button title="Logout" color="red" onPress={() => signOut()} />
      <Toast />
    </View>
  );
}
