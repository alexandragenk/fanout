package model

import "time"

type PostRequest struct {
	Text string `json:"text"`
}

type SubUnsubRequest struct {
	UserID int `json:"user_id"`
}

type FeedItem struct {
	PostID int    `json:"postId"`
	UserID int    `json:"userId"`
	Text   string `json:"text"`
	Likes  int    `json:"likes"`
}

type FeedResponse []FeedItem

type ErrorResponse struct {
	Error string `json:"error"`
}

type Post struct {
	ID        int
	AuthorID  int
	Text      string
	CreatedAt time.Time
}

type Subscription struct {
	FollowerID int
	FolloweeID int
}

type PostAction struct {
	PostID int `json:"postId"`
}

type Like struct {
	UserID int
	PostID int
}
