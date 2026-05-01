package handler

import (
	"encoding/json"
	"feed/internal/middleware"
	"feed/internal/model"
	"feed/internal/service"
	"fmt"
	"net/http"
	"strconv"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type FeedHandler struct {
	svc *service.FeedService
}

func NewFeedHandler(svc *service.FeedService) *FeedHandler {
	return &FeedHandler{svc}
}

func (h *FeedHandler) Router() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /post", h.CreatePost)
	mux.HandleFunc("POST /subscribe", h.Subscribe)
	mux.HandleFunc("POST /unsubscribe", h.Unsubscribe)
	mux.HandleFunc("GET /feed", h.GetFeed)
	mux.HandleFunc("POST /like", h.Like)
	mux.HandleFunc("POST /unlike", h.Unlike)
	mux.HandleFunc("GET /ready", h.Ready)
	mux.Handle("/metrics", promhttp.Handler())
	return middleware.Metrics(mux)
}

func (h *FeedHandler) Ready(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Check(r.Context()); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (h *FeedHandler) Like(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		badRequestError(err, w)
		return
	}

	var req model.PostAction
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequestError(fmt.Errorf("invalid request body"), w)
		return
	}

	if err := h.svc.Like(r.Context(), userID, req.PostID); err != nil {
		internalError(err, w)
		return
	}

	respJSON(w, "ok", http.StatusOK)
}

func (h *FeedHandler) Unlike(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		badRequestError(err, w)
		return
	}

	var req model.PostAction
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequestError(fmt.Errorf("invalid request body"), w)
		return
	}

	if err := h.svc.Unlike(r.Context(), userID, req.PostID); err != nil {
		internalError(err, w)
		return
	}

	respJSON(w, "ok", http.StatusOK)
}

func (h *FeedHandler) CreatePost(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		badRequestError(err, w)
		return
	}

	var req model.PostRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequestError(fmt.Errorf("invalid request body"), w)
		return
	}

	if req.Text == "" {
		badRequestError(fmt.Errorf("text is required"), w)
		return
	}

	if err := h.svc.CreatePost(r.Context(), userID, req.Text); err != nil {
		internalError(err, w)
		return
	}

	respJSON(w, "ok", http.StatusOK)
}

func (h *FeedHandler) Subscribe(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		badRequestError(err, w)
		return
	}

	var req model.SubUnsubRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequestError(fmt.Errorf("invalid request body"), w)
		return
	}

	if err := h.svc.Subscribe(r.Context(), userID, req.UserID); err != nil {
		internalError(err, w)
		return
	}

	respJSON(w, "ok", http.StatusOK)
}

func (h *FeedHandler) Unsubscribe(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		badRequestError(err, w)
		return
	}

	var req model.SubUnsubRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequestError(fmt.Errorf("invalid request body"), w)
		return
	}

	if err := h.svc.Unsubscribe(r.Context(), userID, req.UserID); err != nil {
		internalError(err, w)
		return
	}

	respJSON(w, "ok", http.StatusOK)
}

func (h *FeedHandler) GetFeed(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		badRequestError(err, w)
		return
	}

	countStr := r.URL.Query().Get("count")
	count := 10
	if countStr != "" {
		c, err := strconv.Atoi(countStr)
		if err != nil || c < 0 {
			badRequestError(fmt.Errorf("invalid count parameter: %s", countStr), w)
			return
		}
		count = c
	}

	feed, err := h.svc.GetFeed(r.Context(), userID, count)
	if err != nil {
		internalError(err, w)
		return
	}

	if feed == nil {
		feed = model.FeedResponse{}
	}

	respJSON(w, feed, http.StatusOK)
}

func getUserID(r *http.Request) (int, error) {
	idStr := r.Header.Get("X-User-Id")
	if idStr == "" {
		return 0, fmt.Errorf("X-User-Id header is missing")
	}
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return 0, fmt.Errorf("invalid X-User-Id")
	}
	return id, nil
}

func badRequestError(err error, w http.ResponseWriter) {
	respJSON(w, model.ErrorResponse{Error: err.Error()}, http.StatusBadRequest)
}

func internalError(err error, w http.ResponseWriter) {
	respJSON(w, model.ErrorResponse{Error: err.Error()}, http.StatusInternalServerError)
}

func respJSON(w http.ResponseWriter, resp any, code int) {
	data, err := json.Marshal(resp)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(data)
}
