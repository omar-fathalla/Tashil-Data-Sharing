package branchmaster

// linkAliasNorm maps a normalized short name onto another normalized key so
// Sell-Out headers and Sell-In customers share one proposed code when the
// relationship is already known from Adeco operations. Never invents across
// distinct sites (سموحة ميني stays separate from سموحة).
var linkAliasNorm = map[string]string{
	// Keys MUST already be in Normalize() form (no hamza / ة / separators).
	// Sell-Out "هانوفيل" ↔ Sell-In "الهانوفيل"
	"هانوفيل": "الهانوفيل",
	"نهال فيل":  "الهانوفيل",
	// Sell-Out long Amwaj label ↔ Sell-In أمواج
	"امواج الساحل الشمالي": "امواج",
	// Sell-Out مدينة الرحاب ↔ Sell-In الرحاب
	"مدينه الرحاب": "الرحاب",
	// Sell-Out روزانا ↔ Sell-In قرية روزانا
	"روزانا": "قريه روزانا",
	// Sell-Out النصر ↔ Sell-In ش النصر بلازا
	"النصر": "ش النصر بلازا",
	// Sell-Out طنطا - اوت ليت مول ↔ Sell-In طنطا Out Let
	"طنطا اوت ليت مول": "طنطا out let",
	"طنطا out let":     "طنطا out let",
	// Care-line spelling without space before trailing 2 ↔ grocery «كفر الدوار 2»
	// (owner: مواد عناية + بقالة = same branch).
	"كفر الدوار2": "كفر الدوار 2",
}

// LinkNormalize returns the dry-run grouping key fragment after applying known
// Adeco Sell-Out↔Sell-In bridges on top of Normalize.
func LinkNormalize(raw string) string {
	n := Normalize(raw)
	if n == "" {
		return ""
	}
	if alt, ok := linkAliasNorm[n]; ok {
		return Normalize(alt)
	}
	// Leading definite article ال often differs between SO headers and SI names.
	if stringsHasPrefixAR(n, "ال") && len([]rune(n)) > 3 {
		stripped := stringsTrimPrefixAR(n, "ال")
		if alt, ok := linkAliasNorm[stripped]; ok {
			return Normalize(alt)
		}
		// If the other side already stores without ال, prefer the shorter form
		// only when an explicit reverse alias exists — otherwise keep as-is so
		// الإبراهيمية ≠ الابراهيمية ريفيرا.
	}
	return n
}

func stringsHasPrefixAR(s, p string) bool {
	return len(s) >= len(p) && s[:len(p)] == p
}

func stringsTrimPrefixAR(s, p string) string {
	if stringsHasPrefixAR(s, p) {
		return s[len(p):]
	}
	return s
}
