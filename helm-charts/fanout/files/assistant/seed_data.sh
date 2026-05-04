#!/bin/sh
set -eux

: "${API_URL:?API_URL env var is required}"
: "${NUM_USERS:?NUM_USERS env var is required}"
: "${POSTS_PER_USER:?POSTS_PER_USER env var is required}"

apk add --no-cache curl jq

echo "Starting subscription process..."
for i in $(seq 1 "$NUM_USERS"); do
  for j in $(seq 1 "$NUM_USERS"); do
    if [ "$i" -eq "$j" ]; then continue; fi
    curl -s -X POST "$API_URL/subscribe" \
      -H "X-User-Id: $i" \
      -H "Content-Type: application/json" \
      -d "{\"user_id\": $j}" > /dev/null
  done
  echo "User $i subscribed to all others."
done

echo "Starting post creation..."
for i in $(seq 1 "$NUM_USERS"); do
  for p in $(seq 1 "$POSTS_PER_USER"); do
    curl -s -X POST "$API_URL/post" \
      -H "X-User-Id: $i" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"Post #$p from User #$i\"}" > /dev/null
  done
  echo "User $i created $POSTS_PER_USER posts."
done

echo "Starting like process..."
for i in $(seq 1 "$NUM_USERS"); do
  FEED=$(curl -s "$API_URL/feed?count=2000" -H "X-User-Id: $i")
  POST_IDS=$(echo "$FEED" | jq -r '.[].postId')

  for pid in $POST_IDS; do
    curl -s -X POST "$API_URL/like" \
      -H "X-User-Id: $i" \
      -H "Content-Type: application/json" \
      -d "{\"postId\": $pid}" > /dev/null
  done
done

echo "Done!"
