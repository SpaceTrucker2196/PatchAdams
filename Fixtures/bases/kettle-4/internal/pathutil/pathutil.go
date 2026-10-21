~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
~ synthetic base line 4 ~
~ synthetic base line 5 ~
~ synthetic base line 6 ~
~ synthetic base line 7 ~

// SanitizeName makes a brew name safe to use as a file name.
func SanitizeName(name string) string {
	name = strings.TrimSpace(name)
	name = strings.ReplaceAll(name, "/", "-")
	return strings.ReplaceAll(name, "\\", "-")
