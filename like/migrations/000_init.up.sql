CREATE TABLE likes
(
    id      SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    post_id INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_likes_post_id ON likes (post_id);