package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisCache wraps the connection to the ElastiCache/Redis endpoint
// described by RedisHost/RedisPort in the config file. The application
// is not compatible with Redis Cluster mode, matching the spec.
type RedisCache struct {
	client *redis.Client
}

func NewRedisCache(cfg *Config) *RedisCache {
	if cfg.RedisHost == "" {
		log.Printf("redis: no RedisHost configured, cache lookups will always miss")
		return &RedisCache{}
	}

	addr := fmt.Sprintf("%s:%s", cfg.RedisHost, cfg.RedisPort)
	client := redis.NewClient(&redis.Options{
		Addr:         addr,
		DialTimeout:  3 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
	})

	return &RedisCache{client: client}
}

func (r *RedisCache) Ping(ctx context.Context) error {
	if r.client == nil {
		return fmt.Errorf("redis client not configured")
	}
	return r.client.Ping(ctx).Err()
}

// Get returns the cached value for key, and whether it was found.
func (r *RedisCache) Get(ctx context.Context, key string) (string, bool) {
	if r.client == nil {
		return "", false
	}
	val, err := r.client.Get(ctx, key).Result()
	if err != nil {
		return "", false
	}
	return val, true
}

func (r *RedisCache) Set(ctx context.Context, key, value string) error {
	if r.client == nil {
		return fmt.Errorf("redis client not configured")
	}
	return r.client.Set(ctx, key, value, 0).Err()
}
