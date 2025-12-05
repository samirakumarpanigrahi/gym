import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TextInput, Button } from 'react-native';
import { apiGetComments, apiPostComment } from '../services/api';
import Toast from 'react-native-toast-message';

export default function CommentsScreen({ route }) {
  const { postId } = route.params;
  const [comments, setComments] = useState([]);
  const [text, setText] = useState('');
  useEffect(()=>{ load(); }, []);
  async function load(){ try { const data = await apiGetComments(postId); setComments(data); } catch(e){ console.error(e); } }
  async function submit(){ try { const c = await apiPostComment(postId, text); setComments(prev => [...prev, c]); setText(''); Toast.show({ type: 'success', text1: 'Comment posted' }); } catch(e){ Toast.show({ type: 'error', text1: 'Comment failed' }); } }
  return (
    <View style={{flex:1,padding:12}}>
      <FlatList data={comments} keyExtractor={(i)=>i.id} renderItem={({item})=> (<View style={{padding:8,borderBottomWidth:1,borderColor:'#eee'}}><Text style={{fontWeight:'600'}}>{item.display_name || item.username}</Text><Text>{item.text}</Text></View>)} />
      <TextInput value={text} onChangeText={setText} placeholder="Write a comment" style={{borderWidth:1,borderColor:'#ddd',padding:8,marginVertical:8}} />
      <Button title="Post Comment" onPress={submit} />
      <Toast />
    </View>
  );
}
