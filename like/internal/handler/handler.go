package handler

import (
	"encoding/json"
	"fmt"
	"like/internal/middleware"
	"like/internal/model"
	"like/internal/service"
	"net/http"
	"strconv"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type LikeHandler struct {
	svc *service.LikeService
}

func NewLikeHandler(svc *service.LikeService) *LikeHandler {
	return &LikeHandler{svc: svc}
}

func (h *LikeHandler) Router() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /like", h.Like)
	mux.HandleFunc("POST /unlike", h.Unlike)
	mux.HandleFunc("POST /likes", h.GetLikes)
	mux.HandleFunc("GET /ready", h.Ready)
	mux.Handle("/metrics", promhttp.Handler())
	return middleware.Metrics(mux)
}

func (h *LikeHandler) Ready(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.Check(r.Context()); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (h *LikeHandler) Like(w http.ResponseWriter, r *http.Request) {
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

func (h *LikeHandler) Unlike(w http.ResponseWriter, r *http.Request) {
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

func (h *LikeHandler) GetLikes(w http.ResponseWriter, r *http.Request) {
	var postIDs []int
	if err := json.NewDecoder(r.Body).Decode(&postIDs); err != nil {
		badRequestError(fmt.Errorf("invalid request body"), w)
		return
	}

	counts, err := h.svc.GetLikesCount(r.Context(), postIDs)
	if err != nil {
		internalError(err, w)
		return
	}

	respJSON(w, counts, http.StatusOK)
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
