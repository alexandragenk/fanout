package service

import (
	"context"
	"like_svc/internal/config"
	"like_svc/internal/repository"
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
	counts := make(map[int]int)
	for _, id := range postIDs {
		count, err := s.repo.GetLikeCount(ctx, id)
		if err != nil {
			return nil, err
		}
		counts[id] = count
	}
	return counts, nil
}

func (s *LikeService) Check(ctx context.Context) error {
	return s.repo.Ping(ctx)
}
