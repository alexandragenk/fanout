#!/bin/bash
set -euo pipefail

. config.sh

REPORT_FILE="${REPORT_FILE:-/data/report.json}"
QUERIES_FILE="${PROMQL_QUERIES_FILE:-/config/queries.txt}"
K6_SCRIPT_FILE="${K6_SCRIPT_FILE:-/config-k6/load_k6_feed.js}"

if [[ ! -f "$K6_SCRIPT_FILE" && -f /load_k6_feed.js ]]; then
  K6_SCRIPT_FILE=/load_k6_feed.js
fi

if [[ ! -f "$QUERIES_FILE" ]]; then
  echo "PromQL queries file not found: $QUERIES_FILE" >&2
  exit 1
fi

if [[ ! -f "$K6_SCRIPT_FILE" ]]; then
  echo "k6 script file not found: $K6_SCRIPT_FILE" >&2
  exit 1
fi

k6_output_file=$(mktemp)
trap 'rm -f "$k6_output_file"' EXIT

echo "Starting k6 stress test..."
start=$(date +%s)
k6 run --quiet -e service_url="$service_url" "$K6_SCRIPT_FILE" 2>&1 | tee "$k6_output_file"
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
    | jq -r '.data.result[0].value[1] | try (tonumber | (. * 100 | round / 100)) catch "NaN"'
}

prom_query_range() {
  curl -sG "$prometheus_url/api/v1/query_range" \
    --data-urlencode "query=$1" \
    --data-urlencode "start=$start" \
    --data-urlencode "end=$end" \
    --data-urlencode "step=15" \
    | jq -c '.data.result[0].values // []'
}

for q in "${queries[@]}"; do
  rendered_q="${q//\$duration/$duration}"

  q_max="max_over_time(($rendered_q)[$duration:])"
  q_avg="avg_over_time(($rendered_q)[$duration:])"
  q_series=$(prom_query_range "$rendered_q")

  metrics_agg_json=$(jq \
    --arg query "$rendered_q" \
    --arg max "$(prom_query "$q_max")" \
    --arg avg "$(prom_query "$q_avg")" \
    '. + {($query): {max: $max, avg: $avg}}' <<< "$metrics_agg_json")

  metrics_json=$(jq \
    --arg query "$rendered_q" \
    --argjson values "$q_series" \
    '. + {($query): $values}' <<< "$metrics_json")
done


mkdir -p "$(dirname "$REPORT_FILE")"

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
