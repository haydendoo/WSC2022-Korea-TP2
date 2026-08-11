package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// Storage bundles the two documented storage dependencies of the stub
// service: a filesystem cache directory (FsPath, e.g. an EFS mount) and
// an S3 bucket used to record refund/exception requests.
type Storage struct {
	fsPath string
	bucket string
	s3     *s3.Client
}

func NewStorage(cfg *Config) *Storage {
	s := &Storage{fsPath: cfg.FsPath, bucket: cfg.Bucket}

	if cfg.Bucket == "" {
		log.Printf("storage: no Bucket configured, refund records will not be persisted")
		return s
	}

	awsCfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Printf("storage: unable to load AWS config, S3 disabled: %v", err)
		return s
	}
	s.s3 = s3.NewFromConfig(awsCfg)
	return s
}

// ReadCacheFile reads a cached response body from FsPath, if present.
func (s *Storage) ReadCacheFile(key string) (string, bool) {
	data, err := os.ReadFile(s.cachePath(key))
	if err != nil {
		return "", false
	}
	return string(data), true
}

// WriteCacheFile writes a cached response body under FsPath.
func (s *Storage) WriteCacheFile(key, value string) error {
	if err := os.MkdirAll(s.fsPath, 0o755); err != nil {
		return fmt.Errorf("creating fs path %q: %w", s.fsPath, err)
	}
	return os.WriteFile(s.cachePath(key), []byte(value), 0o644)
}

func (s *Storage) cachePath(key string) string {
	safe := strings.ReplaceAll(key, "/", "_")
	return filepath.Join(s.fsPath, safe+".cache")
}

// PutRefundRecord uploads an exception/refund request to S3, keyed by its
// order UUID, matching the "Request Exception Logs" flow in the Day 2
// architecture diagram.
func (s *Storage) PutRefundRecord(ctx context.Context, orderID string) error {
	if s.s3 == nil {
		return fmt.Errorf("S3 not configured")
	}
	_, err := s.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(orderID),
		Body:   strings.NewReader(orderID),
	})
	return err
}
