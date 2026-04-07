package handler

import (
	"bytes"
	"encoding/json"
	"like_svc/internal/config"
	"like_svc/internal/model"
	"like_svc/internal/repository"
	"like_svc/internal/service"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLikeHandler_Unit(t *testing.T) {
	h := &LikeHandler{}

	t.Run("Missing X-User-Id", func(t *testing.T) {
		req := httptest.NewRequest("POST", "/like", nil)
		rec := httptest.NewRecorder()
		h.Like(rec, req)
		assert.Equal(t, http.StatusBadRequest, rec.Code)
		assert.Contains(t, rec.Body.String(), "X-User-Id header is missing")
	})
}

func TestLikeHandler_Integration(t *testing.T) {
	mux := newLikeMux(t)

	userID := int(time.Now().Unix())
	userIDStr := strconv.Itoa(userID)
	postID := 1001

	// 1. Like
	likeReq := model.PostAction{PostID: postID}
	body, _ := json.Marshal(likeReq)
	req := httptest.NewRequest("POST", "/like", bytes.NewBuffer(body))
	req.Header.Set("X-User-Id", userIDStr)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	// 2. Get Likes Count
	postIDs := []int{postID}
	body, _ = json.Marshal(postIDs)
	req = httptest.NewRequest("POST", "/likes", bytes.NewBuffer(body))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	var counts map[string]int // JSON maps keys are strings
	err := json.Unmarshal(rec.Body.Bytes(), &counts)
	require.NoError(t, err)
	assert.Equal(t, 1, counts[strconv.Itoa(postID)])

	// 3. Unlike
	body, _ = json.Marshal(likeReq)
	req = httptest.NewRequest("POST", "/unlike", bytes.NewBuffer(body))
	req.Header.Set("X-User-Id", userIDStr)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	// 4. Get Likes Count again
	body, _ = json.Marshal(postIDs)
	req = httptest.NewRequest("POST", "/likes", bytes.NewBuffer(body))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)

	err = json.Unmarshal(rec.Body.Bytes(), &counts)
	require.NoError(t, err)
	assert.Equal(t, 0, counts[strconv.Itoa(postID)])
}

func newLikeMux(t *testing.T) http.Handler {
	cfg := &config.LikeConfig{
		DatabaseURI:    "postgres://postgres@localhost:5432/like_svc",
		MigrationsPath: "file://../../migrations",
	}
	repo, err := repository.NewLikeRepo(cfg)
	require.NoError(t, err)
	svc := service.NewLikeService(cfg, repo)
	return NewLikeHandler(svc).Router()
}
