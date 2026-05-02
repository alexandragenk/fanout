package service

import (
	"context"
	"like/internal/config"
	"like/internal/repository"
)

type LikeService struct {
	cfg  *config.LikeConfig
	repo *repository.LikeRepo
}

func NewLikeService(cfg *config.LikeConfig, repo *repository.LikeRepo) *LikeService {
	return &LikeService{
		cfg:  cfg,
		repo: repo,
	}
}

func (s *LikeService) Like(ctx context.Context, userID, postID int) error {
	return s.repo.Like(ctx, userID, postID)
}

func (s *LikeService) Unlike(ctx context.Context, userID, postID int) error {
	return s.repo.Unlike(ctx, userID, postID)
}

func (s *LikeService) GetLikesCount(ctx context.Context, postIDs []int) (map[int]int, error) {
	return s.repo.GetLikesCount(ctx, postIDs)
}

func (s *LikeService) Check(ctx context.Context) error {
	return s.repo.Ping(ctx)
}
