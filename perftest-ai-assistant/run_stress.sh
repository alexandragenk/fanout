#!/bin/bash
set -euo pipefail

. config.sh

echo "Starting k6 stress test..."
K6_SCRIPT_FILE="${K6_SCRIPT_FILE:-$(dirname "$0")/load_k6_feed.js}"
ANALYSIS_PROMPT_FILE="${ANALYSIS_PROMPT_FILE:-$(dirname "$0")/prompts/analysis-prompt.txt}"

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

k6 run -e service_url="$service_url" --duration "$duration" "$K6_SCRIPT_FILE" 2>&1 | tee "$k6_output_file"
k6_output=$(cat "$k6_output_file")

queries=(
)

QUERIES_FILE="${PROMQL_QUERIES_FILE:-$(dirname "$0")/queries.txt}"

if [[ ! -f "$QUERIES_FILE" ]]; then
  echo "PromQL queries file not found: $QUERIES_FILE" >&2
  exit 1
fi

while IFS= read -r line; do
  if [[ -n "$line" && "$line" != \#* ]]; then
    queries+=("$line")
  fi
done < "$QUERIES_FILE"

echo "Collecting Prometheus metrics..."

metrics=""
for q in "${queries[@]}"; do
    rendered_q="${q//\$duration/$duration}"

    value=$(curl -sG "$prometheus_url/api/v1/query" \
      --data-urlencode "query=$rendered_q" \
      | jq -r '.data.result[0].value[1] // "NaN"')
    metrics+="$rendered_q: $value"$'\n'
done

echo "$metrics"

feed_rps=$(curl -sG "$prometheus_url/api/v1/query" \
  --data-urlencode "query=sum(rate(http_request_duration_seconds_count{route='feed'}[$duration]))" \
  | jq -r '.data.result[0].value[1] // "0"')

likes_rps=$(curl -sG "$prometheus_url/api/v1/query" \
  --data-urlencode "query=sum(rate(http_request_duration_seconds_count{route='likes'}[$duration]))" \
  | jq -r '.data.result[0].value[1] // "0"')

if awk "BEGIN { exit !(($feed_rps + $likes_rps) <= 0) }"; then
  echo "WARNING: Prometheus shows zero request rate after k6. LLM analysis will still run, but the report may be invalid."
fi

until curl -sf "$ollama_url/api/tags" | grep -q '"name"'; do
  echo "Waiting for LLM readiness.."
  sleep 1
done

echo "Analyzing..."

prompt_template=$(cat "$ANALYSIS_PROMPT_FILE")
prompt="${prompt_template//\{\{K6_OUTPUT\}\}/$k6_output}"
prompt="${prompt//\{\{PROMETHEUS_METRICS\}\}/$metrics}"

analysis=$(curl -s "$ollama_url/api/generate" -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": $(jq -Rs . <<<"$prompt")
}" | jq -r '.response')

report="=== k6 metrics ==="$'\n'"$k6_output"$'\n\n'"=== Prometheus metrics ==="$'\n'"$metrics"$'\n'"=== LLM analysis ==="$'\n'"$analysis"

echo "$report"

if [ -n "${REPORT_FILE:-}" ]; then
  mkdir -p "$(dirname "$REPORT_FILE")"
  printf "%s\n" "$report" > "$REPORT_FILE"
fi
