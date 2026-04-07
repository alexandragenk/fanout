package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func Metrics(next http.Handler) http.Handler {
	httpDuration := prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"route"},
	)
	httpResponseGroups := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_responses_group_total",
			Help: "HTTP responses groups by url",
		},
		[]string{"route", "group"},
	)
	prometheus.MustRegister(httpDuration, httpResponseGroups)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		route := strings.Trim(r.URL.Path, "/")
		writer := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		start := time.Now()
		next.ServeHTTP(writer, r)
		duration := time.Since(start).Seconds()
		httpDuration.WithLabelValues(route).Observe(duration)
		httpResponseGroups.WithLabelValues(route, fmt.Sprintf("%dxx", writer.status/100)).Inc()
	})
}
