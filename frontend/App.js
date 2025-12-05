import React, { useContext } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import FeedScreen from './screens/FeedScreen';
import WorkoutLoggerScreen from './screens/WorkoutLoggerScreen';
import PublishPostScreen from './screens/PublishPostScreen';
import LoginScreen from './screens/LoginScreen';
import RegisterScreen from './screens/RegisterScreen';
import ProfileScreen from './screens/ProfileScreen';
import ProfileEditScreen from './screens/ProfileEditScreen';
import CommentsScreen from './screens/CommentsScreen';
import NotificationsScreen from './screens/NotificationsScreen';
import { AuthProvider, AuthContext } from './services/AuthContext';
import Toast from 'react-native-toast-message';

const Stack = createNativeStackNavigator();

function AppStack() {
  return (
    <Stack.Navigator initialRouteName="Feed">
      <Stack.Screen name="Feed" component={FeedScreen} />
      <Stack.Screen name="WorkoutLogger" component={WorkoutLoggerScreen} options={{title: 'Workout Logger'}} />
      <Stack.Screen name="PublishPost" component={PublishPostScreen} options={{title: 'Publish Workout'}} />
      <Stack.Screen name="Profile" component={ProfileScreen} options={{title: 'Profile'}} />
    </Stack.Navigator>
  );
}

function AuthStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="Login" component={LoginScreen} />
      <Stack.Screen name="Register" component={RegisterScreen} />
    </Stack.Navigator>
  );
}

function RootNavigator() {
  const { user, loading } = useContext(AuthContext);
  if (loading) return null;
  return user ? <AppStack /> : <AuthStack />;
}

export default function App() {
  return (
    <AuthProvider>
      <NavigationContainer>
        <RootNavigator />
      </NavigationContainer>
    </AuthProvider>
  );
}
