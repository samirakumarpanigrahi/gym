// Simple in-memory store simulating backend operations
let POSTS = [];
let postId = 1;

export function fetchFeed() {
  // return newest first
  return Promise.resolve(POSTS.slice().reverse());
}

export function publishWorkoutPost({author, workout, caption}) {
  const post = {
    id: postId++,
    author: author || {id: 1, username: 'user1', displayName: 'You'},
    createdAt: new Date().toISOString(),
    type: 'workout',
    workout,
    caption,
    likes: 0,
    comments: []
  };
  POSTS.push(post);
  return Promise.resolve(post);
}
