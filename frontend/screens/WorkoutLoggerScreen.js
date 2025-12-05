import React, {useState} from 'react';
import { View, Text, Button, ScrollView, TextInput } from 'react-native';
import ExerciseRow from '../components/ExerciseRow';

export default function WorkoutLoggerScreen({navigation}) {
  const [title, setTitle] = useState('Leg Day');
  const [exercises, setExercises] = useState([
    {name: 'Back Squat', sets: [{reps:5,weight:80},{reps:5,weight:80}]},
    {name: 'Romanian Deadlift', sets: [{reps:8,weight:60},{reps:8,weight:60}]}
  ]);

  function updateExercise(idx, setIdx, newSet) {
    const copy = exercises.slice();
    copy[idx].sets[setIdx] = newSet;
    setExercises(copy);
  }

  function onPublish() {
    const workout = { title, exercises };
    navigation.navigate('PublishPost', {workout});
  }

  return (
    <ScrollView style={{padding:12}}>
      <Text>Title</Text>
      <TextInput value={title} onChangeText={setTitle} style={{borderWidth:1,borderColor:'#ddd',padding:8,marginBottom:12}} />

      {exercises.map((ex, i)=> (
        <ExerciseRow key={i} exercise={ex} onChange={(setIdx, newSet)=> updateExercise(i, setIdx, newSet)} />
      ))}

      <Button title="Publish as Post" onPress={onPublish} />
    </ScrollView>
  );
}
