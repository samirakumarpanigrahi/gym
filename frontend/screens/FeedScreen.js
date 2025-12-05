import React, {useEffect, useState, useContext} from 'react';
import { View, Text, FlatList, Button } from 'react-native';
import PostCard from '../components/PostCard';
import { apiFetchFeed } from '../services/api';
import { AuthContext } from '../services/AuthContext';

export default function FeedScreen({navigation}) {
  const [posts, setPosts] = useState([]);
  const { user } = useContext(AuthContext);

  useEffect(()=>{
    navigation.setOptions({
      headerRight: () => (
        <Button title="Profile" onPress={() => navigation.navigate('Profile')} />
      ),
    });
    const load = async ()=>{ try { const data = await apiFetchFeed(); setPosts(data); } catch(e){ console.error(e); } };
    const unsub = navigation.addListener('focus', load);
    load();
    return unsub;
  }, [navigation]);

  return (
    <View style={{flex:1}}>
      <View style={{padding:12}}>
            <Button title="Notifications" onPress={() => navigation.navigate('Notifications')} />
            <View style={{height:8}} />
        <Button title="Start Workout" onPress={()=>navigation.navigate('WorkoutLogger')} />
        <View style={{height:8}} />
        <Text>Signed in as: {user?.display_name || user?.username}</Text>
      </View>
      <FlatList
        data={posts}
        keyExtractor={(item)=>String(item.id)}
        renderItem={({item})=> <PostCard post={item} />}
      />
    </View>
  );
}
