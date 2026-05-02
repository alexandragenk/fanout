package main

import (
	"like/internal/config"
	"like/internal/handler"
	"like/internal/repository"
	"like/internal/service"
	"log"
	"net/http"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("config path is required as the first argument")
	}
	cfg, err := config.GetLikeConfig(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	repo, err := repository.NewLikeRepo(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer repo.Close()

	svc := service.NewLikeService(cfg, repo)
	h := handler.NewLikeHandler(svc)

	log.Println("Like service is starting at", cfg.RunAddress)
	log.Fatal(http.ListenAndServe(cfg.RunAddress, h.Router()))
}
