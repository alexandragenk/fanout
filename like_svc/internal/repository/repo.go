package repository

import (
	"context"
	"database/sql"
	"like_svc/internal/config"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type LikeRepo struct {
	db *sql.DB
}

func NewLikeRepo(cfg *config.LikeConfig) (*LikeRepo, error) {
	db, err := sql.Open("pgx", cfg.DatabaseURI)
	if err != nil {
		return nil, err
	}
	err = applyMigrations(db, cfg.MigrationsPath)
	if err != nil {
		return nil, err
	}
	return &LikeRepo{
		db: db,
	}, nil
}

func (r *LikeRepo) Like(ctx context.Context, userID, postID int) error {
	_, err := r.db.ExecContext(ctx, "INSERT INTO likes (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", userID, postID)
	return err
}

func (r *LikeRepo) Unlike(ctx context.Context, userID, postID int) error {
	_, err := r.db.ExecContext(ctx, "DELETE FROM likes WHERE user_id = $1 AND post_id = $2", userID, postID)
	return err
}

func (r *LikeRepo) GetLikesCount(ctx context.Context, postIDs []int) (map[int]int, error) {
	counts := make(map[int]int)
	for _, id := range postIDs {
		var count int
		err := r.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM likes WHERE post_id = $1", id).Scan(&count)
		if err != nil {
			return nil, err
		}
		counts[id] = count
	}
	return counts, nil
}

func (r *LikeRepo) Close() error {
	return r.db.Close()
}

func (r *LikeRepo) Ping(ctx context.Context) error {
	return r.db.PingContext(ctx)
}
