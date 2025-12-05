import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import SetRow from './SetRow';

export default function ExerciseRow({exercise, onChange}) {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>{exercise.name}</Text>
      {exercise.sets.map((s, i) => (
        <SetRow key={i} set={s} onChange={(newSet) => onChange && onChange(i, newSet)} />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginBottom: 10 },
  title: { fontWeight: '700', marginBottom: 6 }
});
