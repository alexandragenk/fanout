#!/bin/bash
set -euo pipefail

: "${service_url:?service_url env var is required}"
: "${prometheus_url:?prometheus_url env var is required}"
: "${duration:?duration env var is required}"

REPORT_FILE="${REPORT_FILE:?REPORT_FILE env var is required}"
K6_HTML_REPORT_FILE="${K6_HTML_REPORT_FILE:?K6_HTML_REPORT_FILE env var is required}"
QUERIES_FILE="${PROMQL_QUERIES_FILE:?PROMQL_QUERIES_FILE env var is required}"
K6_SCRIPT_FILE="${K6_SCRIPT_FILE:?K6_SCRIPT_FILE env var is required}"
K6_CONFIG_FILE="${K6_CONFIG_FILE:-/config-k6/config.json}"

if [[ ! -f "$QUERIES_FILE" ]]; then
  echo "PromQL queries file not found: $QUERIES_FILE" >&2
  exit 1
fi

if [[ ! -f "$K6_SCRIPT_FILE" ]]; then
  echo "k6 script file not found: $K6_SCRIPT_FILE" >&2
  exit 1
fi

if [[ ! -f "$K6_CONFIG_FILE" ]]; then
  echo "k6 config file not found: $K6_CONFIG_FILE" >&2
  exit 1
fi

k6_output_file=$(mktemp)
trap 'rm -f "$k6_output_file"' EXIT

echo "Starting k6 stress test..."
start=$(date +%s)
mkdir -p "$(dirname "$REPORT_FILE")" "$(dirname "$K6_HTML_REPORT_FILE")"
K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_PORT=-1 \
K6_WEB_DASHBOARD_EXPORT="$K6_HTML_REPORT_FILE" \
  k6 run --quiet \
    -e service_url="$service_url" \
    -e duration="$duration" \
    -e K6_CONFIG_FILE="$K6_CONFIG_FILE" \
    "$K6_SCRIPT_FILE" 2>&1 | tee "$k6_output_file"
end=$(date +%s)
k6_output=$(cat "$k6_output_file")

queries=()
while IFS= read -r line; do
  if [[ -n "$line" && "$line" != \#* ]]; then
    queries+=("$line")
  fi
done < "$QUERIES_FILE"

metrics_json="{}"
metrics_agg_json="{}"

prom_query() {
  curl -sG "$prometheus_url/api/v1/query" \
    --data-urlencode "query=$1" \
    | jq -c '
        [
          .data.result[]?.value[1]
          | select(. != null and . != "NaN")
          | tonumber
        ] as $values
        | if ($values | length) == 0 then
            null
          else
            ($values | add | (. * 100 | round / 100))
          end
      '
}

prom_query_range() {
  curl -sG "$prometheus_url/api/v1/query_range" \
    --data-urlencode "query=$1" \
    --data-urlencode "start=$start" \
    --data-urlencode "end=$end" \
    --data-urlencode "step=15" \
    | jq -c '
        [
          .data.result[]?.values[]?
          | select(.[1] != null and .[1] != "NaN")
          | {ts: .[0], value: (.[1] | tonumber)}
        ]
        | group_by(.ts)
        | map([
            .[0].ts,
            (map(.value) | add)
          ])
      '
}

for q in "${queries[@]}"; do
  q_max="max_over_time(($q)[$duration:])"
  q_avg="avg_over_time(($q)[$duration:])"
  q_series=$(prom_query_range "$q")

  metrics_agg_json=$(jq \
    --arg query "$q" \
    --argjson max "$(prom_query "$q_max")" \
    --argjson avg "$(prom_query "$q_avg")" \
    '. + {($query): {max: $max, avg: $avg}}' <<< "$metrics_agg_json")

  metrics_json=$(jq \
    --arg query "$q" \
    --argjson values "$q_series" \
    '. + {($query): $values}' <<< "$metrics_json")
done

jq -n \
  --arg k6_output "$k6_output" \
  --argjson metrics "$metrics_json" \
  --argjson metrics_agg "$metrics_agg_json" \
  '{
    k6_output: $k6_output,
    metrics: $metrics,
    metrics_agg: $metrics_agg
  }' > "$REPORT_FILE"

cat "$REPORT_FILE"
