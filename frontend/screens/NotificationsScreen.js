import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, Button } from 'react-native';
import { apiGetNotifications, apiMarkNotificationRead } from '../services/api';
import Toast from 'react-native-toast-message';

export default function NotificationsScreen() {
  const [notifs, setNotifs] = useState([]);
  useEffect(()=>{ load(); }, []);
  async function load(){ try { const data = await apiGetNotifications(); setNotifs(data); } catch(e){ console.error(e); } }
  async function markRead(id){ try { await apiMarkNotificationRead(id); Toast.show({ type: 'success', text1: 'Marked read' }); load(); } catch(e){ Toast.show({ type: 'error', text1: 'Action failed' }); } }
  return (
    <View style={{flex:1,padding:12}}>
      <FlatList data={notifs} keyExtractor={(i)=>i.id} renderItem={({item})=> (
        <View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}>
          <Text style={{fontWeight:'700'}}>{item.verb} • {item.display_name || item.username}</Text>
          <Text>{item.data && item.data.text}</Text>
          {!item.is_read && <Button title="Mark read" onPress={()=>markRead(item.id)} />}
        </View>
      )} />
      <Toast />
    </View>
  );
}
