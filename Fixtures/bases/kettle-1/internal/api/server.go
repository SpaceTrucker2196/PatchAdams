~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
~ synthetic base line 4 ~
~ synthetic base line 5 ~
~ synthetic base line 6 ~
~ synthetic base line 7 ~
~ synthetic base line 8 ~
~ synthetic base line 9 ~
~ synthetic base line 10 ~
~ synthetic base line 11 ~
~ synthetic base line 12 ~
~ synthetic base line 13 ~
~ synthetic base line 14 ~
~ synthetic base line 15 ~
	h := handler.NewBrewHandler(svc)
	mux.HandleFunc("POST /brews", h.Add)
	mux.HandleFunc("GET /brews", h.List)
	return &Server{mux: mux}
}

