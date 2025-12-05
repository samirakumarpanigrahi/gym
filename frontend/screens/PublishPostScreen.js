import React, {useState} from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { apiCreateWorkout, apiPublishWorkout } from '../services/api';

export default function PublishPostScreen({route, navigation}) {
  const {workout} = route.params;
  const [caption, setCaption] = useState(`${workout.title} — great session!`);
  const [loading, setLoading] = useState(false);

  async function onPublish() {
    try {
      setLoading(true);
      // create workout
      const res = await apiCreateWorkout({ title: workout.title, exercises: workout.exercises });
      const workoutId = res.id;
      // publish
      await apiPublishWorkout(workoutId, caption);
      setLoading(false);
      navigation.navigate('Feed');
    } catch (e) {
      setLoading(false);
      Alert.alert('Publish failed', JSON.stringify(e));
    }
  }

  return (
    <View style={{padding:12}}>
      <Text>Caption</Text>
      <TextInput value={caption} onChangeText={setCaption} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginVertical:12}} multiline />
      <Button title={loading ? 'Publishing...' : 'Publish'} onPress={onPublish} disabled={loading} />
    </View>
  );
}
