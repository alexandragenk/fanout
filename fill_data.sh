#!/bin/bash

API_URL="http://localhost:8080"
NUM_USERS=16
POSTS_PER_USER=16

echo "Starting subscription process (32 users, each subscribing to others)..."
for i in $(seq 1 $NUM_USERS); do
  for j in $(seq 1 $NUM_USERS); do
    if [ "$i" -eq "$j" ]; then continue; fi
    curl -s -X POST "$API_URL/subscribe" \
      -H "X-User-Id: $i" \
      -H "Content-Type: application/json" \
      -d "{\"user_id\": $j}" > /dev/null
  done
  echo "User $i subscribed to all others."
done

echo "Starting post creation (each of 32 users creating 32 posts)..."
for i in $(seq 1 $NUM_USERS); do
  for p in $(seq 1 $POSTS_PER_USER); do
    curl -s -X POST "$API_URL/post" \
      -H "X-User-Id: $i" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"Post #$p from User #$i\"}" > /dev/null
  done
  echo "User $i created $POSTS_PER_USER posts."
done

# exit

echo "Starting like process (each user liking all posts from their feed)..."
for i in $(seq 1 $NUM_USERS); do
  # Получаем ленту пользователя (лимит 2000, чтобы захватить все 1024 поста)
  FEED=$(curl -s -X GET "$API_URL/feed?count=2000" -H "X-User-Id: $i")
  
  # Извлекаем все postId из JSON ответа с помощью jq
  POST_IDS=$(echo "$FEED" | jq -r '.[].postId')
  
  echo "User $i liking $(echo "$POST_IDS" | wc -l) posts..."
  for pid in $POST_IDS; do
    curl -s -X POST "$API_URL/like" \
      -H "X-User-Id: $i" \
      -H "Content-Type: application/json" \
      -d "{\"postId\": $pid}" > /dev/null
  done
  echo "User $i finished liking."
done

echo "Done!"
