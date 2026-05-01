package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type LikeConfig struct {
	RunAddress     string `yaml:"run_address"`
	DatabaseURI    string `yaml:"database_uri"`
	MigrationsPath string `yaml:"migrations_path"`
}

func GetLikeConfig(path string) (*LikeConfig, error) {
	cfg := &LikeConfig{}
	if err := loadConfigFromFile(path, cfg); err != nil {
		return nil, err
	}
	cfg.RunAddress = os.ExpandEnv(cfg.RunAddress)
	cfg.DatabaseURI = os.ExpandEnv(cfg.DatabaseURI)
	cfg.MigrationsPath = os.ExpandEnv(cfg.MigrationsPath)
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
