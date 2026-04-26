#!/bin/bash
set -euo pipefail

. config.sh

REPORT_FILE="${REPORT_FILE:-/data/report.json}"
QUERIES_FILE="${PROMQL_QUERIES_FILE:-/config/queries.txt}"
K6_SCRIPT_FILE="${K6_SCRIPT_FILE:-/config-k6/load_k6_feed.js}"
ANALYSIS_PROMPT_FILE="${ANALYSIS_PROMPT_FILE:-/config-prompts/analysis-prompt.txt}"

if [[ ! -f "$QUERIES_FILE" && -f /queries.txt ]]; then
  QUERIES_FILE=/queries.txt
fi

if [[ ! -f "$K6_SCRIPT_FILE" && -f /load_k6_feed.js ]]; then
  K6_SCRIPT_FILE=/load_k6_feed.js
fi

if [[ ! -f "$ANALYSIS_PROMPT_FILE" && -f /prompts/analysis-prompt.txt ]]; then
  ANALYSIS_PROMPT_FILE=/prompts/analysis-prompt.txt
fi

if [[ ! -f "$QUERIES_FILE" ]]; then
  echo "PromQL queries file not found: $QUERIES_FILE" >&2
  exit 1
fi

if [[ ! -f "$K6_SCRIPT_FILE" ]]; then
  echo "k6 script file not found: $K6_SCRIPT_FILE" >&2
  exit 1
fi

if [[ ! -f "$ANALYSIS_PROMPT_FILE" ]]; then
  echo "Analysis prompt file not found: $ANALYSIS_PROMPT_FILE" >&2
  exit 1
fi

k6_output_file=$(mktemp)
trap 'rm -f "$k6_output_file"' EXIT

echo "Starting k6 stress test..."
k6 run -e service_url="$service_url" "$K6_SCRIPT_FILE" 2>&1 | tee "$k6_output_file"
k6_output=$(cat "$k6_output_file")

queries=()
while IFS= read -r line; do
  if [[ -n "$line" && "$line" != \#* ]]; then
    queries+=("$line")
  fi
done < "$QUERIES_FILE"

metrics_json="{}"

for q in "${queries[@]}"; do
  rendered_q="${q//\$duration/$duration}"

  value=$(curl -sG "$prometheus_url/api/v1/query" \
    --data-urlencode "query=$rendered_q" \
    | jq -r '.data.result[0].value[1] // "NaN"')

  metrics_json=$(jq \
    --arg query "$rendered_q" \
    --arg value "$value" \
    '. + {($query): $value}' <<< "$metrics_json")
done

prompt_template=$(cat "$ANALYSIS_PROMPT_FILE")
prompt="${prompt_template//\{\{K6_OUTPUT\}\}/$k6_output}"
prompt="${prompt//\{\{PROMETHEUS_METRICS\}\}/$(
  jq -r '
    to_entries
    | map("\(.key): \(.value)")
    | join("\n")
  ' <<< "$metrics_json"
)}"

mkdir -p "$(dirname "$REPORT_FILE")"

jq -n \
  --arg duration "$duration" \
  --arg service_url "$service_url" \
  --arg k6_output "$k6_output" \
  --arg analysis_prompt "$prompt" \
  --argjson metrics "$metrics_json" \
  '{
    duration: $duration,
    service_url: $service_url,
    k6_output: $k6_output,
    prometheus_metrics: $metrics,
    analysis_prompt: $analysis_prompt
  }' > "$REPORT_FILE"

cat "$REPORT_FILE"
