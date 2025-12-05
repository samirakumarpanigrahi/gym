import React from 'react';
import { View, TextInput, Text, StyleSheet } from 'react-native';

export default function SetRow({set, onChange}) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>Reps</Text>
      <TextInput style={styles.input} value={String(set.reps)} keyboardType="numeric" onChangeText={(t)=>onChange({...set,reps: parseInt(t||0)})} />
      <Text style={styles.label}>Kg</Text>
      <TextInput style={styles.input} value={String(set.weight)} keyboardType="numeric" onChangeText={(t)=>onChange({...set,weight: parseFloat(t||0)})} />
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', marginBottom: 6 },
  label: { width: 40 },
  input: { borderWidth: 1, borderColor: '#ddd', padding: 6, width: 80, marginRight: 12 }
});
