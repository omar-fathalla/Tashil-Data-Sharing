package bqsink

import (
	"encoding/json"
	"reflect"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
)

// Standard load-metadata columns added to every sink table. Struct fields with
// the same JSON name are skipped so these always carry sink-controlled values.
const (
	ColTenantID      = "tenant_id"
	ColBatchID       = "batch_id"
	ColArchiveID     = "archive_id"
	ColSourceFile    = "source_file"
	ColIngestedAt    = "ingested_at"
	ColPartitionDate = "partition_date"
	ColPeriodMonth   = "period_month"
	ColChainKey      = "chain_key"
)

var metaFields = []*bigquery.FieldSchema{
	{Name: ColTenantID, Type: bigquery.StringFieldType, Required: true},
	{Name: ColBatchID, Type: bigquery.StringFieldType},
	{Name: ColArchiveID, Type: bigquery.StringFieldType},
	{Name: ColSourceFile, Type: bigquery.StringFieldType},
	{Name: ColIngestedAt, Type: bigquery.TimestampFieldType, Required: true},
	{Name: ColPartitionDate, Type: bigquery.DateFieldType},
	{Name: ColPeriodMonth, Type: bigquery.StringFieldType},
	{Name: ColChainKey, Type: bigquery.StringFieldType},
}

func isMetaName(name string) bool {
	for _, f := range metaFields {
		if f.Name == name {
			return true
		}
	}
	return false
}

var timeType = reflect.TypeOf(time.Time{})

type fieldInfo struct {
	name  string
	index []int
	typ   reflect.Type
}

func jsonName(f reflect.StructField) string {
	tag := f.Tag.Get("json")
	if tag == "-" || tag == "" {
		return ""
	}
	name := strings.Split(tag, ",")[0]
	if name == "" {
		return ""
	}
	return name
}

func collectFields(t reflect.Type, prefix []int, out *[]fieldInfo, seen map[string]bool) {
	for i := 0; i < t.NumField(); i++ {
		f := t.Field(i)
		idx := append(append([]int{}, prefix...), i)
		if f.Anonymous && f.Type.Kind() == reflect.Struct && f.Type != timeType {
			collectFields(f.Type, idx, out, seen)
			continue
		}
		if !f.IsExported() {
			continue
		}
		name := jsonName(f)
		if name == "" || isMetaName(name) || seen[name] {
			continue
		}
		seen[name] = true
		*out = append(*out, fieldInfo{name: name, index: idx, typ: f.Type})
	}
}

func fieldsOf(sample interface{}) []fieldInfo {
	t := reflect.TypeOf(sample)
	for t.Kind() == reflect.Ptr {
		t = t.Elem()
	}
	var out []fieldInfo
	collectFields(t, nil, &out, map[string]bool{})
	return out
}

func bqType(t reflect.Type) (bigquery.FieldType, bool) {
	for t.Kind() == reflect.Ptr {
		t = t.Elem()
	}
	if t == timeType {
		return bigquery.TimestampFieldType, false
	}
	switch t.Kind() {
	case reflect.String:
		return bigquery.StringFieldType, false
	case reflect.Bool:
		return bigquery.BooleanFieldType, false
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint8, reflect.Uint16, reflect.Uint32:
		return bigquery.IntegerFieldType, false
	case reflect.Float32, reflect.Float64:
		return bigquery.FloatFieldType, false
	case reflect.Slice:
		if t.Elem().Kind() == reflect.String {
			return bigquery.StringFieldType, true
		}
	}
	// Anything else (maps, nested structs, slices of structs) is stored as JSON text.
	return bigquery.StringFieldType, false
}

// SchemaFor derives a BigQuery schema from a domain struct's JSON tags plus the standard meta columns.
func SchemaFor(sample interface{}) bigquery.Schema {
	schema := bigquery.Schema{}
	for _, m := range metaFields {
		c := *m
		schema = append(schema, &c)
	}
	for _, f := range fieldsOf(sample) {
		typ, repeated := bqType(f.typ)
		schema = append(schema, &bigquery.FieldSchema{Name: f.name, Type: typ, Repeated: repeated})
	}
	return schema
}

const bqTimestampLayout = "2006-01-02T15:04:05.000000Z07:00"

// RowFor converts a domain struct to a JSON-ready map matching SchemaFor (excluding meta columns).
func RowFor(v interface{}) map[string]interface{} {
	rv := reflect.ValueOf(v)
	for rv.Kind() == reflect.Ptr {
		rv = rv.Elem()
	}
	row := make(map[string]interface{})
	for _, f := range fieldsOf(rv.Interface()) {
		fv := rv.FieldByIndex(f.index)
		for fv.Kind() == reflect.Ptr {
			if fv.IsNil() {
				break
			}
			fv = fv.Elem()
		}
		if fv.Kind() == reflect.Ptr && fv.IsNil() {
			row[f.name] = nil
			continue
		}
		typ, repeated := bqType(f.typ)
		switch {
		case fv.Type() == timeType:
			tm := fv.Interface().(time.Time)
			if tm.IsZero() {
				row[f.name] = nil
			} else {
				row[f.name] = tm.UTC().Format(bqTimestampLayout)
			}
		case repeated:
			arr := make([]string, 0, fv.Len())
			for i := 0; i < fv.Len(); i++ {
				arr = append(arr, fv.Index(i).String())
			}
			row[f.name] = arr
		case typ == bigquery.StringFieldType && fv.Kind() != reflect.String:
			b, _ := json.Marshal(fv.Interface())
			row[f.name] = string(b)
		default:
			row[f.name] = fv.Interface()
		}
	}
	return row
}
