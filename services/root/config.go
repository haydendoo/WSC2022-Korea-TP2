package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/appconfigdata"
)

// Config mirrors the "Root Server Configuration" documented in the Day 2
// test project (Service Details -> Example Configuration). Per the spec,
// "all unicorn applications need to communicate to AWS AppConfig Service
// in order to get configuration" - the JSON shape below is what AppConfig
// is expected to deliver.
type Config struct {
	RedisHost string `json:"RedisHost"`
	RedisPort string `json:"RedisPort"`
	FsPath    string `json:"FsPath"`
	Port      int    `json:"Port"`
	Bucket    string `json:"Bucket"`
}

const defaultPort = 80

func normalize(cfg *Config) *Config {
	if cfg.Port == 0 {
		cfg.Port = defaultPort
	}
	if cfg.FsPath == "" {
		cfg.FsPath = "./"
	}
	return cfg
}

// LoadConfigFromFile reads a JSON config file from disk. This is a
// local-development convenience (e.g. docker-compose) for exercising the
// binary without a real AppConfig application - it is not how the
// competition intends configuration to be delivered.
func LoadConfigFromFile(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config file %q: %w", path, err)
	}
	cfg := &Config{}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parsing config file %q: %w", path, err)
	}
	return normalize(cfg), nil
}

// AppConfigIdentifiers names the AWS AppConfig application/environment/
// configuration profile that hold this service's configuration. AppConfig
// itself is a participant-provisioned resource (see terraform scope notes
// in the README) - this binary only needs to know where to look.
type AppConfigIdentifiers struct {
	Application string
	Environment string
	Profile     string
}

func (a AppConfigIdentifiers) complete() bool {
	return a.Application != "" && a.Environment != "" && a.Profile != ""
}

// LoadConfigFromAppConfig fetches configuration from AWS AppConfig using
// the AppConfigData "session" API (StartConfigurationSession +
// GetLatestConfiguration), which is the AWS-recommended replacement for
// the deprecated appconfig:GetConfiguration call.
func LoadConfigFromAppConfig(ctx context.Context, ids AppConfigIdentifiers) (*Config, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}
	client := appconfigdata.NewFromConfig(awsCfg)

	session, err := client.StartConfigurationSession(ctx, &appconfigdata.StartConfigurationSessionInput{
		ApplicationIdentifier:                aws.String(ids.Application),
		EnvironmentIdentifier:                aws.String(ids.Environment),
		ConfigurationProfileIdentifier:       aws.String(ids.Profile),
		RequiredMinimumPollIntervalInSeconds: aws.Int32(15),
	})
	if err != nil {
		return nil, fmt.Errorf("starting AppConfig session: %w", err)
	}

	latest, err := client.GetLatestConfiguration(ctx, &appconfigdata.GetLatestConfigurationInput{
		ConfigurationToken: session.InitialConfigurationToken,
	})
	if err != nil {
		return nil, fmt.Errorf("fetching AppConfig configuration: %w", err)
	}

	cfg := &Config{}
	if err := json.Unmarshal(latest.Configuration, cfg); err != nil {
		return nil, fmt.Errorf("parsing AppConfig configuration payload: %w", err)
	}
	return normalize(cfg), nil
}
