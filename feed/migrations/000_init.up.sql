CREATE TABLE subs
(
    follower_id INTEGER NOT NULL,
    followee_id INTEGER NOT NULL,
    PRIMARY KEY (follower_id, followee_id)
);

CREATE INDEX idx_subscriptions_followee
    ON subs (followee_id);

CREATE TABLE posts
(
    id         SERIAL PRIMARY KEY,
    author_id  INTEGER   NOT NULL,
    text       TEXT      NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_posts_author_created
    ON posts (author_id, created_at DESC);

CREATE TABLE feeds
(
    user_id    INTEGER   NOT NULL,
    post_id    INTEGER   NOT NULL,
    created_at TIMESTAMP NOT NULL,
    PRIMARY KEY (user_id, post_id)
);

CREATE INDEX idx_feeds_user_created
    ON feeds (user_id, created_at DESC);