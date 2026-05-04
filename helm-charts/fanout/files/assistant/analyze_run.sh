#!/bin/bash
set -euo pipefail

: "${ollama_url:?ollama_url env var is required}"

LLM_TEMPERATURE="${LLM_TEMPERATURE:-0.1}"
RUN_REPORT_FILE="${RUN_REPORT_FILE:?RUN_REPORT_FILE env var is required}"
HTML_REPORT_FILE="${HTML_REPORT_FILE:?HTML_REPORT_FILE env var is required}"
HTML_TEMPLATE_FILE="${HTML_TEMPLATE_FILE:?HTML_TEMPLATE_FILE env var is required}"
RUN_ANALYSIS_PROMPT_FILE="${RUN_ANALYSIS_PROMPT_FILE:?RUN_ANALYSIS_PROMPT_FILE env var is required}"

if [[ ! -f "$RUN_REPORT_FILE" ]]; then
  echo "Run report file not found: $RUN_REPORT_FILE" >&2
  exit 1
fi

if [[ ! -f "$RUN_ANALYSIS_PROMPT_FILE" ]]; then
  echo "Run analysis prompt file not found: $RUN_ANALYSIS_PROMPT_FILE" >&2
  exit 1
fi

if [[ ! -f "$HTML_TEMPLATE_FILE" ]]; then
  echo "HTML template file not found: $HTML_TEMPLATE_FILE" >&2
  exit 1
fi

run_report=$(cat "$RUN_REPORT_FILE")
k6_output=$(jq -r '.k6_output // ""' <<< "$run_report")
metrics_agg=$(jq -r '
  (.metrics_agg // {})
  | to_entries[]
  | "\(.key): avg=\(.value.avg // "null"), max=\(.value.max // "null")"
' <<< "$run_report")

until curl -sf "$ollama_url/api/tags" | grep -q '"name"'; do
  echo "Waiting for LLM readiness..."
  sleep 2
done

prompt=$(jq -Rn \
  --rawfile template "$RUN_ANALYSIS_PROMPT_FILE" \
  --arg k6_output "$k6_output" \
  --arg metrics_agg "$metrics_agg" \
  '$template
    | gsub("\\$k6_output"; $k6_output)
    | gsub("\\$metrics_agg"; $metrics_agg)')

echo "$prompt"

payload=$(jq -n \
  --arg prompt "$prompt" \
  --argjson temperature "$LLM_TEMPERATURE" \
  '{
    model: "default",
    stream: false,
    prompt: $prompt,
    options: {
      temperature: $temperature,
      top_p: 0.9,
      repeat_penalty: 1.1
    }
  }')

analysis=$(curl -s "$ollama_url/api/generate" -d "$payload" | jq -r '.response')
analysis_json=$(jq -Rs . <<< "$analysis")

generated_at=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
run_metrics_json=$(jq -c '.metrics' <<< "$run_report")
metrics_json=$(jq -cn --argjson run "$run_metrics_json" '{"": $run}')

jq -Rrn \
  --rawfile template "$HTML_TEMPLATE_FILE" \
  --arg generated_at "$generated_at" \
  --argjson metrics "$metrics_json" \
  --argjson analysis "$analysis_json" \
  '$template
    | gsub("__REPORT_DATE__"; $generated_at)
    | gsub("__METRICS_JSON__"; ($metrics | tojson))
    | gsub("__ANALYSIS_JSON__"; ($analysis | tojson))' \
  > "$HTML_REPORT_FILE"

echo "HTML report saved to $HTML_REPORT_FILE"
