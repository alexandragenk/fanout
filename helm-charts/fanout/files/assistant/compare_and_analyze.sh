#!/bin/bash
set -euo pipefail

: "${ollama_url:?ollama_url env var is required}"

BASELINE_FILE="${BASELINE_FILE:?BASELINE_FILE env var is required}"
CANDIDATE_FILE="${CANDIDATE_FILE:?CANDIDATE_FILE env var is required}"
HTML_REPORT_FILE="${HTML_REPORT_FILE:?HTML_REPORT_FILE env var is required}"
HTML_TEMPLATE_FILE="${HTML_TEMPLATE_FILE:?HTML_TEMPLATE_FILE env var is required}"
COMPARISON_PROMPT_FILE="${COMPARISON_PROMPT_FILE:?COMPARISON_PROMPT_FILE env var is required}"

if [[ ! -f "$COMPARISON_PROMPT_FILE" ]]; then
  echo "Comparison prompt file not found: $COMPARISON_PROMPT_FILE" >&2
  exit 1
fi

if [[ ! -f "$HTML_TEMPLATE_FILE" ]]; then
  echo "HTML template file not found: $HTML_TEMPLATE_FILE" >&2
  exit 1
fi

baseline=$(cat "$BASELINE_FILE")
candidate=$(cat "$CANDIDATE_FILE")

baseline_k6=$(jq -r '.k6_output' <<< "$baseline")
candidate_k6=$(jq -r '.k6_output' <<< "$candidate")
baseline_metrics=$(jq -r '
  .metrics_agg
  | to_entries
  | map("\(.key): avg=\(.value.avg), max=\(.value.max)")
  | join("\n")
' <<< "$baseline")
candidate_metrics=$(jq -r '
  .metrics_agg
  | to_entries
  | map("\(.key): avg=\(.value.avg), max=\(.value.max)")
  | join("\n")
' <<< "$candidate")

until curl -sf "$ollama_url/api/tags" | grep -q '"name"'; do
  echo "Waiting for LLM readiness..."
  sleep 2
done

prompt=$(cat "$COMPARISON_PROMPT_FILE")
prompt="${prompt//\{\{BASELINE_K6\}\}/$baseline_k6}"
prompt="${prompt//\{\{CANDIDATE_K6\}\}/$candidate_k6}"
prompt="${prompt//\{\{BASELINE_METRICS\}\}/$baseline_metrics}"
prompt="${prompt//\{\{CANDIDATE_METRICS\}\}/$candidate_metrics}"

echo "$prompt"

analysis_json=$(curl -s "$ollama_url/api/generate" -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": $(jq -Rs . <<< "$prompt")
}" | jq -c '.response')

generated_at=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
baseline_metrics_json=$(jq -c '.metrics' <<< "$baseline")
candidate_metrics_json=$(jq -c '.metrics' <<< "$candidate")

html_report=$(cat "$HTML_TEMPLATE_FILE")
html_report="${html_report//__REPORT_DATE__/$generated_at}"
html_report="${html_report//__BASELINE_METRICS_JSON__/$baseline_metrics_json}"
html_report="${html_report//__CANDIDATE_METRICS_JSON__/$candidate_metrics_json}"
html_report="${html_report//__ANALYSIS_JSON__/$analysis_json}"

printf "%s\n" "$html_report" > "$HTML_REPORT_FILE"

echo "HTML report saved to $HTML_REPORT_FILE"
