package branchnorm

// Entry is one canonical branch definition. Slug must stay frozen to match
// existing fat_/gom_/… StoreIDs produced by gemini.BuildBranchStoreMetadata.
type Entry struct {
	CanonicalAR string
	CanonicalEN string
	Slug        string
	Governorate string
	City        string
}

// catalog is the source of truth for known branches (Arabic display + frozen slug).
var catalog = []Entry{
	{"سموحة", "Smouha", "smouha", "الإسكندرية", "سموحة"},
	{"سموحة ميني", "Smouha Mini", "smouha_mini", "الإسكندرية", "سموحة"},
	{"جاردينيا", "Gardenia", "gardenia", "الإسكندرية", "جاردينيا"},
	{"هانوفيل", "Hanoville", "hanoville", "الإسكندرية", "العجمي - هانوفيل"},
	{"أكتوبر", "October", "october", "الجيزة", "السادس من أكتوبر"},
	{"طنطا", "Tanta", "tanta", "الغربية", "طنطا"},
	{"طنطا - اوت ليت مول", "Tanta Outlet Mall", "tanta_outlet", "الغربية", "طنطا"},
	{"عجمي ستار", "Agamy Star", "agamy_star", "الإسكندرية", "العجمي"},
	{"الإبراهيمية", "Ibrahimia", "ibrahimia", "الإسكندرية", "الإبراهيمية"},
	{"الإبراهيمية ميني", "Ibrahimia Mini", "ibrahimia_mini", "الإسكندرية", "الإبراهيمية"},
	{"سيدي جابر ميني", "Sidi Gaber Mini", "sidi_gaber_mini", "الإسكندرية", "سيدي جابر"},
	{"سيدي جابر المحطة", "Sidi Gaber Station", "sidi_gaber_station", "الإسكندرية", "سيدي جابر"},
	{"كفر الدوار", "Kafr El Dawar", "kafr_eldawar", "البحيرة", "كفر الدوار"},
	{"كفر الدوار - مول", "Kafr El Dawar Mall", "kafr_eldawar_mall", "البحيرة", "كفر الدوار"},
	{"مطروح", "Matrouh", "matrouh", "مرسى مطروح", "مطروح"},
	{"دمنهور الأندلس", "Damanhour Andalus", "damanhour_andalus", "البحيرة", "دمنهور"},
	{"دمنهور - الاستاد", "Damanhour Stadium", "damanhour_stadium", "البحيرة", "دمنهور"},
	{"الأنفوشي", "Anfoushy", "anfoushy", "الإسكندرية", "الأنفوشي"},
	{"المحلة الكبرى", "El Mahalla", "mahalla", "الغربية", "المحلة الكبرى"},
	{"فلمنج", "Fleming", "fleming", "الإسكندرية", "فلمنج"},
	{"الدخيلة ميني", "Dekheila Mini", "dekheila_mini", "الإسكندرية", "الدخيلة"},
	{"الدخيلة مينى 2", "Dekheila Mini 2", "dekheila_mini_2", "الإسكندرية", "الدخيلة"},
	{"سيدي بشر ميني", "Sidi Bishr Mini", "sidi_bishr_mini", "الإسكندرية", "سيدي بشر"},
	{"روزانا", "Rozana", "rozana", "الإسكندرية", "سموحة - روزانا"},
	{"النصر", "El Nasr", "elnasr", "الإسكندرية", "شارع النصر"},
	{"طوسون", "Toson", "toson", "الإسكندرية", "أبو قير - طوسون"},
	{"ابو يوسف", "Abu Youssef", "abu_youssef", "الإسكندرية", "العجمي - أبو يوسف"},
	{"ستانلي", "Stanley", "stanley", "الإسكندرية", "ستانلي"},
	{"أمواج - الساحل الشمالي", "Amwaj North Coast", "amwaj_north_coast", "الساحل الشمالي", "أمواج"},
	{"ملك حفنى", "Malak Hefny", "malak_hefny", "الإسكندرية", "ملك حفني"},
	{"سيتي سكوير", "City Square", "city_square", "الإسكندرية", "سيتي سكوير"},
	{"مدينة الرحاب", "Rehab City", "rehab_city", "القاهرة", "مدينة الرحاب"},
	{"نيس2", "Nice 2", "nice_2", "الإسكندرية", "نيس"},
	{"دمياط الجديدة", "New Damietta", "new_damietta", "دمياط", "دمياط الجديدة"},
	{"المعادي", "Maadi", "maadi", "القاهرة", "المعادي"},
	{"الدقي", "Dokki", "dokki", "الجيزة", "الدقي"},
	{"مدينة نصر", "Nasr City", "nasr_city", "القاهرة", "مدينة نصر"},
}

// aliasRaw maps extra raw spellings (not already Key(entry.CanonicalAR) or EN)
// onto the same catalog entry. Keys are produced via Key().
var aliasRaw = []struct {
	raw   string
	canon string // CanonicalAR of target
}{
	// Hanoville misspellings / alternate names already in production sheets
	{"نهال فيل", "هانوفيل"},
	{"نهال فيلة", "هانوفيل"},
	{"hanoville", "هانوفيل"},
	{"hanovel", "هانوفيل"},
	{"agamy hanoville", "هانوفيل"},

	// Smouha variants
	{"سموحه", "سموحة"},
	{"سموحه ميني", "سموحة ميني"},
	{"سموحة mini", "سموحة ميني"},
	{"smouha mini", "سموحة ميني"},
	{"فرع سموحة", "سموحة"},
	{"فر. سموحة", "سموحة"},
	{"فر سموحة", "سموحة"},

	// Stanley
	{"ستانلى", "ستانلي"},
	{"stanley alex", "ستانلي"},
	{"st. stanley", "ستانلي"},
	{"st stanley", "ستانلي"},
	{"فرع ستانلي", "ستانلي"},
	{"فرع ستانلى", "ستانلي"},


	// Gardenia
	{"جاردينيا ميني", "جاردينيا"}, // no separate mini slug historically
	{"gardenia alex", "جاردينيا"},

	// October
	{"6 اكتوبر", "أكتوبر"},
	{"6 أكتوبر", "أكتوبر"},
	{"السادس من أكتوبر", "أكتوبر"},
	{"6th october", "أكتوبر"},
	{"october 6", "أكتوبر"},
	{"6 october", "أكتوبر"},
	{"october", "أكتوبر"},

	// Full English names (also registered via CanonicalEN; kept for clarity)
	{"smouha", "سموحة"},
	{"gardenia", "جاردينيا"},
	{"stanley", "ستانلي"},
	{"tanta", "طنطا"},
	{"maadi", "المعادي"},
	{"dokki", "الدقي"},


	// Tanta outlet
	{"طنطا اوتليت", "طنطا - اوت ليت مول"},
	{"طنطا outlet", "طنطا - اوت ليت مول"},
	{"tanta outlet", "طنطا - اوت ليت مول"},

	// Mahalla
	{"المحلة", "المحلة الكبرى"},
	{"المحله", "المحلة الكبرى"},
	{"المحله الكبري", "المحلة الكبرى"},
	{"el mahalla", "المحلة الكبرى"},

	// Maadi / Dokki / Nasr (common English sell-out headers)
	{"carrefour maadi", "المعادي"},
	{"maadi city center", "المعادي"},
	{"dokki", "الدقي"},
	{"nasr city", "مدينة نصر"},
	{"مدينة نصر القاهرة", "مدينة نصر"},

	// Amwaj
	{"امواج", "أمواج - الساحل الشمالي"},
	{"أمواج", "أمواج - الساحل الشمالي"},
	{"amwaj", "أمواج - الساحل الشمالي"},

	// Fleming
	{"fleming", "فلمنج"},
	{"فلمنج ميني", "فلمنج"},

	// Ibrahimia
	{"الابراهيمية", "الإبراهيمية"},
	{"ibrahimia mini", "الإبراهيمية ميني"},

	// Dekheila mini 2 spelling
	{"الدخيلة ميني 2", "الدخيلة مينى 2"},
	{"dekheila mini 2", "الدخيلة مينى 2"},
}

var (
	byKey    map[string]Entry
	aliasKey map[string]string // Key(raw) → CanonicalAR
)

func init() {
	byKey = make(map[string]Entry, len(catalog)*3)
	aliasKey = make(map[string]string, len(aliasRaw)+len(catalog)*2)
	for _, e := range catalog {
		k := Key(e.CanonicalAR)
		byKey[k] = e
		aliasKey[k] = e.CanonicalAR
		if e.CanonicalEN != "" {
			ek := Key(e.CanonicalEN)
			byKey[ek] = e
			aliasKey[ek] = e.CanonicalAR
		}
	}
	for _, a := range aliasRaw {
		target, ok := lookupCanon(a.canon)
		if !ok {
			continue
		}
		k := Key(a.raw)
		byKey[k] = target
		aliasKey[k] = target.CanonicalAR
	}
}

func lookupCanon(canonicalAR string) (Entry, bool) {
	for _, e := range catalog {
		if e.CanonicalAR == canonicalAR {
			return e, true
		}
	}
	return Entry{}, false
}
