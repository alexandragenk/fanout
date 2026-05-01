package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"feed/internal/config"
	"feed/internal/model"
	"feed/internal/repository"
	"feed/internal/service"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHandler_Integration(t *testing.T) {
	mux := newMux(t)

	authorID := time.Now().Unix()
	subId := strconv.FormatInt(authorID, 10)
	postText := "integration test post"

	// 1. Subscribe
	subReq := model.SubUnsubRequest{UserID: int(authorID)}
	body, _ := json.Marshal(subReq)
	req := httptest.NewRequest("POST", "/subscribe", bytes.NewBuffer(body))
	req.Header.Set("X-User-Id", subId)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	// 2. Create Post
	postReq := model.PostRequest{Text: postText}
	body, _ = json.Marshal(postReq)
	req = httptest.NewRequest("POST", "/post", bytes.NewBuffer(body))
	req.Header.Set("X-User-Id", strconv.FormatInt(authorID, 10))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	// 3. Get Feed
	req = httptest.NewRequest("GET", "/feed?count=10", nil)
	req.Header.Set("X-User-Id", subId)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	var feed model.FeedResponse
	err := json.Unmarshal(rec.Body.Bytes(), &feed)
	require.NoError(t, err)

	assert.True(t, len(feed) > 0)
	assert.Equal(t, int(authorID), feed[0].UserID)
	assert.Equal(t, postText, feed[0].Text)
}

func newMux(t *testing.T) http.Handler {
	cfg := &config.FeedConfig{
		DatabaseURI:    "postgres://postgres@feed-db:5432/feed",
		MigrationsPath: "file://../../migrations",
	}
	repo, err := repository.NewFeedRepo(cfg)
	require.NoError(t, err)
	return NewFeedHandler(service.NewFeedService(cfg, repo, &LikeClientMock{})).Router()
}

type LikeClientMock struct {
}

func (m *LikeClientMock) GetLikes(context.Context, []int) (map[int]int, error) {
	return map[int]int{}, nil
}

func (m *LikeClientMock) Like(context.Context, int, int) error {
	return nil
}

func (m *LikeClientMock) Unlike(context.Context, int, int) error {
	return nil
}
