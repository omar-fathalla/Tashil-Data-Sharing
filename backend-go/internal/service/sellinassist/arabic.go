package sellinassist

import "strings"

func normalizeArabic(s string) string {
	s = strings.TrimSpace(s)
	s = strings.NewReplacer("أ", "ا", "إ", "ا", "آ", "ا", "ة", "ه", "ى", "ي").Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

func normalizeHeaderLabel(s string) string {
	s = strings.ToLower(normalizeArabic(s))
	s = strings.NewReplacer("_", " ", "-", " ", ".", " ").Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

func containsAny(hay string, needles ...string) bool {
	for _, n := range needles {
		if n != "" && strings.Contains(hay, n) {
			return true
		}
	}
	return false
}
