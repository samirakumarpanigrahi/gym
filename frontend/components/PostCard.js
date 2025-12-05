import React, { useState, useContext } from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { AuthContext } from '../services/AuthContext';
import { useNavigation } from '@react-navigation/native';
import { apiToggleLike } from '../services/api';

export default function PostCard({post}) {
  const navigation = useNavigation();
  const { user } = useContext(AuthContext);
  const [likes, setLikes] = useState(post.likes_count || 0);
  const [commentsCount, setCommentsCount] = useState(post.comments_count || 0);
  const [liked, setLiked] = useState(false);

  async function onLike() {
    try {
      const res = await apiToggleLike(post.id);
      setLiked(res.liked);
      setLikes(prev => res.liked ? prev + 1 : Math.max(prev - 1, 0));
    } catch (e) { console.error('like error', e); }
  }

  return (
    <View style={styles.card}>
      <Text style={styles.author}>{post.author.displayName} • {new Date(post.createdAt).toLocaleString()}</Text>
      <Text style={styles.caption}>{post.caption}</Text>
      <View style={styles.workoutSummary}>
        <Text style={styles.wTitle}>{post.workout.title || 'Workout'}</Text>
        <Text>{post.workout.exercises?.length || 0} exercises • {post.workout.total_volume ?? 0} kg total</Text>
      </View>

      <View style={styles.actions}>
        <TouchableOpacity onPress={onLike}><Text>{liked ? '❤️' : '🤍'} {likes}</Text></TouchableOpacity>
        <TouchableOpacity onPress={() => navigation.navigate('Comments', { postId: post.id })}><Text>💬 {commentsCount}</Text></TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { padding: 12, borderBottomWidth: 1, borderColor: '#eee' },
  author: { fontWeight: '600', marginBottom: 6 },
  caption: { marginBottom: 8 },
  workoutSummary: { backgroundColor: '#fafafa', padding: 8, borderRadius: 6 },
  wTitle: { fontWeight: '700' },
  actions: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 8 }
});
