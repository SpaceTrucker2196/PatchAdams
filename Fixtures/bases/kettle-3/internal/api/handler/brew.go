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
~ synthetic base line 16 ~
~ synthetic base line 17 ~
~ synthetic base line 18 ~
~ synthetic base line 19 ~
~ synthetic base line 20 ~
~ synthetic base line 21 ~
~ synthetic base line 22 ~
~ synthetic base line 23 ~
~ synthetic base line 24 ~
~ synthetic base line 25 ~
~ synthetic base line 26 ~
~ synthetic base line 27 ~
~ synthetic base line 28 ~
	json.NewEncoder(w).Encode(brew)
}

// List handles GET /brews.
func (h *BrewHandler) List(w http.ResponseWriter, r *http.Request) {
	brews, err := h.svc.ListBrews()
