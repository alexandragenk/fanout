package repository

import (
	"database/sql"
	"fmt"
	"log"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func applyMigrations(db *sql.DB, migrationsPath string) error {
	log.Println("Applying migrations...")
	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		return fmt.Errorf("failed to init driver: %w", err)
	}

	m, err := migrate.NewWithDatabaseInstance(migrationsPath, "postgres", driver)
	if err != nil {
		return fmt.Errorf("failed to init migrate: %w", err)
	}

	err = m.Up()
	switch err {
	case nil:
		log.Println("Migrations applied successfully.")
		return nil
	case migrate.ErrNoChange:
		log.Println("Database is up to date.")
		return nil
	default:
		return fmt.Errorf("migration failed: %v", err)
	}
}
