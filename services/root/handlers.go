package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

// Server holds the dependencies needed to answer requests: cache (Redis),
// storage (filesystem + S3). This is a practice stand-in for the real
// "root" binary described in the Day 2 spec, not a reproduction of it.
type Server struct {
	cfg     *Config
	cache   *RedisCache
	storage *Storage
}

func NewServer(cfg *Config, cache *RedisCache, storage *Storage) *Server {
	return &Server{cfg: cfg, cache: cache, storage: storage}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", s.handleHealth)
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("GET /unicorns/{id}", s.handleGetUnicorn)
	mux.HandleFunc("POST /refund", s.handleRefund)
	return mux
}

// handleHealth is the documented health check: "root path (/) for health
// check ... once you get HTTP 200 response from root path, it attests
// that your application is running normally."
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"service": "root",
		"status":  "ok",
	})
}

// handleGetUnicorn demonstrates the documented cache-through path:
// Redis -> filesystem -> generate, so participants have something
// concrete to exercise once Redis/EFS are wired up.
func (s *Server) handleGetUnicorn(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	if val, ok := s.cache.Get(ctx, id); ok {
		writeUnicorn(w, id, val, "redis")
		return
	}

	if val, ok := s.storage.ReadCacheFile(id); ok {
		if err := s.cache.Set(ctx, id, val); err != nil {
			log.Printf("warn: could not repopulate redis for %q: %v", id, err)
		}
		writeUnicorn(w, id, val, "filesystem")
		return
	}

	location := fmt.Sprintf("generated-location-%s", id)
	if err := s.storage.WriteCacheFile(id, location); err != nil {
		log.Printf("warn: could not write cache file for %q: %v", id, err)
	}
	if err := s.cache.Set(ctx, id, location); err != nil {
		log.Printf("warn: could not populate redis for %q: %v", id, err)
	}
	writeUnicorn(w, id, location, "generated")
}

func writeUnicorn(w http.ResponseWriter, id, location, source string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"unicornid":       id,
		"unicornlocation": location,
		"source":          source,
	})
}

// handleRefund persists a refund/exception request to S3, matching the
// "Request Exception Logs" arrow in the Day 2 architecture diagram.
func (s *Server) handleRefund(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Order string `json:"order"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Order == "" {
		http.Error(w, `{"error":"missing \"order\" field"}`, http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	if err := s.storage.PutRefundRecord(ctx, body.Order); err != nil {
		log.Printf("error: could not store refund record: %v", err)
		http.Error(w, `{"error":"could not store refund record"}`, http.StatusServiceUnavailable)
		return
	}

	w.WriteHeader(http.StatusCreated)
}
