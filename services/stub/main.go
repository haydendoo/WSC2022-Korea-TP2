// Command stub is a practice-compatible stand-in for the "stub" server
// binary described in the WorldSkills WSC2022 TP53 Day 2 test project.
//
// It is NOT the original competition binary: it is a from-scratch Go
// implementation that reproduces the documented interface (flags, config
// source, health check, port behaviour, dependencies) closely enough to
// exercise the infrastructure participants build (AppConfig, Secrets
// Manager, MySQL/RDS, filesystem/EFS mount, S3). Business logic and exact
// response bodies are illustrative, not a reverse-engineering of the
// proprietary original.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
)

const usage = `stub - Unicorn Service "stub" practice server

USAGE:
  stub [flags]

FLAGS:
  --appconfig-application string   AppConfig application identifier (name or ID)
  --appconfig-environment string   AppConfig environment identifier (name or ID)
  --appconfig-profile string       AppConfig configuration profile identifier (name or ID)
  --config string                  Local JSON config file, used only if the
                                    --appconfig-* flags are not all set
                                    (local-development convenience, see
                                    config/stub.example.json)
  --port int                       TCP port to listen on, overrides the
                                    resolved config (default 80)
  --help                           Show this help message and exit

ENVIRONMENT VARIABLES (equivalent to the flags above):
  APPCONFIG_APPLICATION, APPCONFIG_ENVIRONMENT, APPCONFIG_PROFILE, CONFIG_FILE, PORT

CONFIGURATION:
  Per the Day 2 spec, this service is expected to fetch its configuration
  from AWS AppConfig. Provide --appconfig-application/--appconfig-environment
  /--appconfig-profile (or the equivalent env vars) to fetch live config
  from AppConfig. If those are not all set, stub falls back to reading a
  local JSON file (--config, default "config.json") - handy for local
  testing (see docker/docker-compose.yaml), not how the competition
  environment is expected to run.

  Config JSON shape (delivered by AppConfig or the local file):
  {
    "DBSecretArn": "arn:aws:secretsmanager:region:accountid:secret:prod-XXXXXX",
    "DBName": "unicorndb",
    "FsPath": "./",
    "Bucket": "unicorn-refund-bucket",
    "Port": 80
  }

DEPENDENCIES:
  - AWS AppConfig for configuration.
  - AWS Secrets Manager (DBSecretArn) for rotated MySQL credentials.
  - MySQL (RDS) with a "unicorns" table, see database/schema.sql.
  - A filesystem path (FsPath) for cached files, e.g. an EFS mount.
  - An S3 bucket for refund/exception request records.

ENDPOINTS:
  GET  /               health check, returns HTTP 200 when the process is up
  GET  /healthz         alias for /
  GET  /unicorns/{id}   cache-through demo across MySQL and FsPath
  POST /refund           {"order":"<uuid>"} - records a refund/exception to S3
`

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	appConfigApp := flag.String("appconfig-application", envOrDefault("APPCONFIG_APPLICATION", ""), "AppConfig application identifier")
	appConfigEnv := flag.String("appconfig-environment", envOrDefault("APPCONFIG_ENVIRONMENT", ""), "AppConfig environment identifier")
	appConfigProfile := flag.String("appconfig-profile", envOrDefault("APPCONFIG_PROFILE", ""), "AppConfig configuration profile identifier")
	configPath := flag.String("config", envOrDefault("CONFIG_FILE", "config.json"), "local JSON config file (fallback when AppConfig flags are unset)")
	portOverride := flag.Int("port", 0, "TCP port to listen on (overrides resolved config)")
	help := flag.Bool("help", false, "show help")
	flag.Usage = func() { fmt.Fprint(os.Stderr, usage) }
	flag.Parse()

	if *help {
		fmt.Print(usage)
		return
	}

	ids := AppConfigIdentifiers{Application: *appConfigApp, Environment: *appConfigEnv, Profile: *appConfigProfile}

	var cfg *Config
	var err error
	if ids.complete() {
		log.Printf("stub: fetching configuration from AWS AppConfig (application=%s environment=%s profile=%s)",
			ids.Application, ids.Environment, ids.Profile)
		cfg, err = LoadConfigFromAppConfig(context.Background(), ids)
	} else {
		log.Printf("stub: --appconfig-* flags not fully set, falling back to local config file %q", *configPath)
		cfg, err = LoadConfigFromFile(*configPath)
	}
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	if *portOverride != 0 {
		cfg.Port = *portOverride
	} else if p := os.Getenv("PORT"); p != "" {
		fmt.Sscanf(p, "%d", &cfg.Port)
	}

	db, err := NewDB(context.Background(), cfg)
	if err != nil {
		log.Printf("warn: database unavailable at startup, unicorn lookups will fall back to filesystem: %v", err)
		db = nil
	}
	storage := NewStorage(cfg)
	server := NewServer(cfg, db, storage)

	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("stub: listening on %s (fsPath=%s bucket=%s dbSecretArn=%s)",
		addr, cfg.FsPath, cfg.Bucket, cfg.DBSecretArn)

	if err := http.ListenAndServe(addr, server.Routes()); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
