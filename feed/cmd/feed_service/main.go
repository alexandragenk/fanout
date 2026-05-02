package main

import (
	"feed/internal/config"
	"feed/internal/handler"
	"feed/internal/repository"
	"feed/internal/service"
	"log"
	"net/http"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("config path is required as the first argument")
	}
	cfg, err := config.GetFeedConfig(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	repo, err := repository.NewFeedRepo(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer repo.Close()

	likeClient := service.NewLikeHTTPClient(cfg)
	svc := service.NewFeedService(cfg, repo, likeClient)
	s := handler.NewFeedHandler(svc)
	log.Println("Feed service is starting at", cfg.RunAddress)
	log.Fatal(http.ListenAndServe(cfg.RunAddress, s.Router()))
}
