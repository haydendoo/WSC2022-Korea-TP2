package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	_ "github.com/go-sql-driver/mysql"
)

// dbSecret is the shape of an AWS Secrets Manager secret produced by RDS's
// built-in credential rotation (the "database credential should be
// automatically rotated every 30 days" requirement from the spec).
type dbSecret struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Host     string `json:"host"`
	Port     int    `json:"port"`
	DBName   string `json:"dbname"`
}

// DB wraps the MySQL connection described by DBSecretArn/DBName in the
// config file, and manages the single "unicorns" table the spec requires.
type DB struct {
	sql *sql.DB
}

// NewDB resolves credentials from Secrets Manager (DBSecretArn) and opens
// a connection to the database named by cfg.DBName.
func NewDB(ctx context.Context, cfg *Config) (*DB, error) {
	if cfg.DBSecretArn == "" {
		return nil, fmt.Errorf("no DBSecretArn configured")
	}

	secret, err := fetchDBSecret(ctx, cfg.DBSecretArn)
	if err != nil {
		return nil, fmt.Errorf("fetching DB secret: %w", err)
	}

	dbName := cfg.DBName
	if dbName == "" {
		dbName = secret.DBName
	}

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?parseTime=true&timeout=5s",
		secret.Username, secret.Password, secret.Host, secret.Port, dbName)

	sqlDB, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("opening database: %w", err)
	}
	sqlDB.SetConnMaxLifetime(5 * time.Minute)

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := sqlDB.PingContext(pingCtx); err != nil {
		return nil, fmt.Errorf("connecting to database: %w", err)
	}

	return &DB{sql: sqlDB}, nil
}

func fetchDBSecret(ctx context.Context, secretArn string) (*dbSecret, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}
	client := secretsmanager.NewFromConfig(awsCfg)

	out, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: &secretArn,
	})
	if err != nil {
		return nil, err
	}

	secret := &dbSecret{}
	if err := json.Unmarshal([]byte(*out.SecretString), secret); err != nil {
		return nil, fmt.Errorf("parsing secret payload: %w", err)
	}
	if secret.Port == 0 {
		secret.Port = 3306
	}
	return secret, nil
}

// GetUnicorn looks up a cached unicornlocation by unicornid from the
// "unicorns" table (see database/schema.sql - the table name and columns
// are fixed by the spec and cannot be changed).
func (d *DB) GetUnicorn(ctx context.Context, id string) (string, bool, error) {
	var location string
	err := d.sql.QueryRowContext(ctx,
		`SELECT unicornlocation FROM unicorns WHERE unicornid = ?`, id,
	).Scan(&location)
	if err == sql.ErrNoRows {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return location, true, nil
}

// UpsertUnicorn inserts a new unicornid/unicornlocation pair.
func (d *DB) UpsertUnicorn(ctx context.Context, id, location string) error {
	_, err := d.sql.ExecContext(ctx,
		`INSERT INTO unicorns (unicornid, unicornlocation) VALUES (?, ?)`, id, location)
	return err
}

func (d *DB) Ping(ctx context.Context) error {
	return d.sql.PingContext(ctx)
}
