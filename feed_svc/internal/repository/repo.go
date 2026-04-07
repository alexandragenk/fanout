package repository

import (
	"context"
	"database/sql"
	"feed_svc/internal/config"
	"feed_svc/internal/model"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type FeedRepo struct {
	db *sql.DB
}

func NewFeedRepo(cfg *config.FeedConfig) (*FeedRepo, error) {
	db, err := sql.Open("pgx", cfg.DatabaseURI)
	if err != nil {
		return nil, err
	}
	err = applyMigrations(db, cfg.MigrationsPath)
	if err != nil {
		return nil, err
	}
	return &FeedRepo{
		db: db,
	}, nil
}

func (r *FeedRepo) CreatePost(ctx context.Context, authorID int, text string) (int, time.Time, error) {
	var id int
	var createdAt time.Time
	err := r.db.QueryRowContext(ctx, "INSERT INTO posts (author_id, text) VALUES ($1, $2) RETURNING id, created_at", authorID, text).Scan(&id, &createdAt)
	return id, createdAt, err
}

func (r *FeedRepo) Subscribe(ctx context.Context, followerID, followeeID int) error {
	_, err := r.db.ExecContext(ctx, "INSERT INTO subs (follower_id, followee_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", followerID, followeeID)
	return err
}

func (r *FeedRepo) Unsubscribe(ctx context.Context, followerID, followeeID int) error {
	_, err := r.db.ExecContext(ctx, "DELETE FROM subs WHERE follower_id = $1 AND followee_id = $2", followerID, followeeID)
	return err
}

func (r *FeedRepo) GetFollowers(ctx context.Context, followeeID int) ([]int, error) {
	rows, err := r.db.QueryContext(ctx, "SELECT follower_id FROM subs WHERE followee_id = $1", followeeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var followers []int
	for rows.Next() {
		var f int
		if err := rows.Scan(&f); err != nil {
			return nil, err
		}
		followers = append(followers, f)
	}
	return followers, nil
}

func (r *FeedRepo) AddToFeeds(ctx context.Context, postID int, userIDs []int, createdAt time.Time) error {
	if len(userIDs) == 0 {
		return nil
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	stmt, err := tx.PrepareContext(ctx, "INSERT INTO feeds (user_id, post_id, created_at) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()
	for _, uID := range userIDs {
		if _, err := stmt.ExecContext(ctx, uID, postID, createdAt); err != nil {
			tx.Rollback()
			return err
		}
	}
	return tx.Commit()
}

func (r *FeedRepo) GetFeed(ctx context.Context, userID int, limit int) (model.FeedResponse, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT f.post_id, p.author_id, p.text 
		FROM feeds f 
		JOIN posts p ON f.post_id = p.id 
		WHERE f.user_id = $1 
		ORDER BY f.created_at DESC 
		LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var feed model.FeedResponse
	for rows.Next() {
		var item model.FeedItem
		if err := rows.Scan(&item.PostID, &item.UserID, &item.Text); err != nil {
			return nil, err
		}
		feed = append(feed, item)
	}
	return feed, nil
}

func (r *FeedRepo) Close() error {
	return r.db.Close()
}

func (r *FeedRepo) Ping(ctx context.Context) error {
	return r.db.PingContext(ctx)
}
