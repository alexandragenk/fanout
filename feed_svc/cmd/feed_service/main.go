package main

import (
	"feed_svc/internal/config"
	"feed_svc/internal/handler"
	"feed_svc/internal/repository"
	"feed_svc/internal/service"
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
