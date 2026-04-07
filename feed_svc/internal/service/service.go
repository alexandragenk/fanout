package service

import (
	"context"
	"feed_svc/internal/config"
	"feed_svc/internal/model"
	"feed_svc/internal/repository"
)

type FeedService struct {
	repo       *repository.FeedRepo
	cfg        *config.FeedConfig
	likeClient LikeClient
}

func NewFeedService(cfg *config.FeedConfig, repo *repository.FeedRepo, likeClient LikeClient) *FeedService {
	return &FeedService{
		repo:       repo,
		cfg:        cfg,
		likeClient: likeClient,
	}
}

func (s *FeedService) CreatePost(ctx context.Context, authorID int, text string) error {
	postID, createdAt, err := s.repo.CreatePost(ctx, authorID, text)
	if err != nil {
		return err
	}

	followers, err := s.repo.GetFollowers(ctx, authorID)
	if err != nil {
		return err
	}

	recipients := append(followers, authorID)
	return s.repo.AddToFeeds(ctx, postID, recipients, createdAt)
}

func (s *FeedService) Subscribe(ctx context.Context, followerID, followeeID int) error {
	return s.repo.Subscribe(ctx, followerID, followeeID)
}

func (s *FeedService) Unsubscribe(ctx context.Context, followerID, followeeID int) error {
	return s.repo.Unsubscribe(ctx, followerID, followeeID)
}

func (s *FeedService) GetFeed(ctx context.Context, userID int, limit int) (model.FeedResponse, error) {
	feed, err := s.repo.GetFeed(ctx, userID, limit)
	if err != nil {
		return nil, err
	}

	if len(feed) == 0 {
		return feed, nil
	}

	postIDs := make([]int, len(feed))
	for i, item := range feed {
		postIDs[i] = item.PostID
	}

	likes, err := s.likeClient.GetLikes(ctx, postIDs)
	if err != nil {
		return nil, err
	}

	for i := range feed {
		feed[i].Likes = likes[feed[i].PostID]
	}

	return feed, nil
}

func (s *FeedService) Like(ctx context.Context, userID, postID int) error {
	return s.likeClient.Like(ctx, userID, postID)
}

func (s *FeedService) Unlike(ctx context.Context, userID, postID int) error {
	return s.likeClient.Unlike(ctx, userID, postID)
}

func (s *FeedService) Check(ctx context.Context) error {
	return s.repo.Ping(ctx)
}
