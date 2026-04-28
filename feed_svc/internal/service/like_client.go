package service

import (
	"bytes"
	"context"
	"encoding/json"
	"feed_svc/internal/config"
	"feed_svc/internal/model"
	"fmt"
	"io"
	"net/http"
)

type LikeClient interface {
	GetLikes(ctx context.Context, postIDs []int) (map[int]int, error)
	Like(ctx context.Context, userID, postID int) error
	Unlike(ctx context.Context, userID, postID int) error
}

type LikeHTTPClient struct {
	cfg        *config.FeedConfig
	httpClient *http.Client
}

func NewLikeHTTPClient(cfg *config.FeedConfig) *LikeHTTPClient {
	return &LikeHTTPClient{
		cfg:        cfg,
		httpClient: &http.Client{},
	}
}

func (c *LikeHTTPClient) GetLikes(ctx context.Context, postIDs []int) (map[int]int, error) {
	body, err := json.Marshal(postIDs)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.cfg.LikeServiceURL+"/likes", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}
		return nil, fmt.Errorf("like service returned status %d, body: %s", resp.StatusCode, string(bodyBytes))
	}

	var likes map[int]int
	if err := json.NewDecoder(resp.Body).Decode(&likes); err != nil {
		return nil, err
	}

	return likes, nil
}

func (c *LikeHTTPClient) Like(ctx context.Context, userID, postID int) error {
	return c.proxyLikeAction(ctx, userID, postID, "/like")
}

func (c *LikeHTTPClient) Unlike(ctx context.Context, userID, postID int) error {
	return c.proxyLikeAction(ctx, userID, postID, "/unlike")
}

func (c *LikeHTTPClient) proxyLikeAction(ctx context.Context, userID, postID int, path string) error {
	body, err := json.Marshal(model.PostAction{PostID: postID})
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.cfg.LikeServiceURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-User-Id", fmt.Sprintf("%d", userID))

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("like service returned status %d", resp.StatusCode)
	}

	return nil
}
