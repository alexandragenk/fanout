package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type FeedConfig struct {
	RunAddress     string `yaml:"run_address"`
	DatabaseURI    string `yaml:"database_uri"`
	MigrationsPath string `yaml:"migrations_path"`
	LikeServiceURL string `yaml:"like_service_url"`
}

func GetFeedConfig(path string) (*FeedConfig, error) {
	cfg := &FeedConfig{}
	if err := loadConfigFromFile(path, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func loadConfigFromFile(path string, cfg any) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	return yaml.NewDecoder(f).Decode(cfg)
}
