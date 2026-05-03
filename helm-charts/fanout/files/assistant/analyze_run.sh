#!/bin/bash
set -euo pipefail

: "${ollama_url:?ollama_url env var is required}"

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
metrics_agg=$(jq -r '
  (.metrics_agg // {})
  | to_entries[]
  | "\(.key): avg=\(.value.avg // "null"), max=\(.value.max // "null")"
' <<< "$run_report")

until curl -sf "$ollama_url/api/tags" | grep -q '"name"'; do
  echo "Waiting for LLM readiness..."
  sleep 2
done

prompt=$(cat "$RUN_ANALYSIS_PROMPT_FILE")
prompt="${prompt//\$metrics_agg/$metrics_agg}"

echo "$prompt"

analysis=$(curl -s "$ollama_url/api/generate" -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": $(jq -Rs . <<< "$prompt")
}" | jq -r '.response')
analysis_json=$(jq -Rs . <<< "$analysis")

generated_at=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
run_metrics_json=$(jq -c '.metrics' <<< "$run_report")
metrics_json=$(jq -cn --argjson run "$run_metrics_json" '{"": $run}')

html_report=$(cat "$HTML_TEMPLATE_FILE")
html_report="${html_report//__REPORT_DATE__/$generated_at}"
html_report="${html_report//__METRICS_JSON__/$metrics_json}"
html_report="${html_report//__ANALYSIS_JSON__/$analysis_json}"

printf "%s\n" "$html_report" > "$HTML_REPORT_FILE"

echo "HTML report saved to $HTML_REPORT_FILE"
