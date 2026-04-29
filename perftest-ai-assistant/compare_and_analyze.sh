#!/bin/bash
set -euo pipefail

. config.sh

BASELINE_FILE="${BASELINE_FILE:-/data/old-report.json}"
CANDIDATE_FILE="${CANDIDATE_FILE:-/data/new-report.json}"
REPORT_FILE="${REPORT_FILE:-/data/final-report.txt}"
HTML_REPORT_FILE="${HTML_REPORT_FILE:-/data/final-report.html}"
HTML_TEMPLATE_FILE="${HTML_TEMPLATE_FILE:-/template.html}"
COMPARISON_PROMPT_FILE="${COMPARISON_PROMPT_FILE:-/config-prompts/comparison-prompt.txt}"

if [[ ! -f "$COMPARISON_PROMPT_FILE" && -f /prompts/comparison-prompt.txt ]]; then
  COMPARISON_PROMPT_FILE=/prompts/comparison-prompt.txt
fi

if [[ ! -f "$COMPARISON_PROMPT_FILE" ]]; then
  echo "Comparison prompt file not found: $COMPARISON_PROMPT_FILE" >&2
  exit 1
fi

if [[ ! -f "$HTML_TEMPLATE_FILE" && -f ./template.html ]]; then
  HTML_TEMPLATE_FILE=./template.html
fi

if [[ ! -f "$HTML_TEMPLATE_FILE" ]]; then
  echo "HTML template file not found: $HTML_TEMPLATE_FILE" >&2
  exit 1
fi

baseline=$(cat "$BASELINE_FILE")
candidate=$(cat "$CANDIDATE_FILE")

comparison=$(jq -n \
  --argjson baseline "$baseline" \
  --argjson candidate "$candidate" \
  '
  {
    baseline_metrics_count: ($baseline.metrics_agg | length),
    candidate_metrics_count: ($candidate.metrics_agg | length),
    comparison: [
      $baseline.metrics_agg
      | keys[]
      | . as $key
      | {
          query: $key,
          baseline: ($baseline.metrics_agg[$key].avg),
          candidate: ($candidate.metrics_agg[$key].avg),
          diff: (
            (($candidate.metrics_agg[$key].avg | tonumber?) as $candidate_avg
            | ($baseline.metrics_agg[$key].avg | tonumber?) as $baseline_avg
            | if $candidate_avg == null or $baseline_avg == null then
                null
              else
                ($candidate_avg - $baseline_avg)
              end)
          )
        }
    ]
  }')

comparison_lines=$(jq -r '
  .comparison[]
  | "\(.query)\n  baseline=\(.baseline)\n  candidate=\(.candidate)\n  diff=\(.diff)"
' <<< "$comparison")

top_regressions=$(jq -r '
  .comparison
  | map(select(.diff != null))
  | sort_by(.diff)
  | reverse
  | .[:5]
  | .[]
  | "\(.query) | baseline=\(.baseline) | candidate=\(.candidate) | diff=\(.diff)"
' <<< "$comparison")

top_improvements=$(jq -r '
  .comparison
  | map(select(.diff != null))
  | sort_by(.diff)
  | .[:5]
  | .[]
  | "\(.query) | baseline=\(.baseline) | candidate=\(.candidate) | diff=\(.diff)"
' <<< "$comparison")

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

prompt_template=$(cat "$COMPARISON_PROMPT_FILE")
prompt="${prompt_template//\{\{BASELINE_K6\}\}/$baseline_k6}"
prompt="${prompt//\{\{CANDIDATE_K6\}\}/$candidate_k6}"
prompt="${prompt//\{\{COMPARISON_LINES\}\}/$comparison_lines}"
prompt="${prompt//\{\{TOP_REGRESSIONS\}\}/$top_regressions}"
prompt="${prompt//\{\{TOP_IMPROVEMENTS\}\}/$top_improvements}"

analysis=$(curl -s "$ollama_url/api/generate" -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": $(jq -Rs . <<< "$prompt")
}" | jq -r '.response')

summary_json=$(jq '
  {
    total: (.comparison | length),
    regressions: ([.comparison[] | select(.diff != null and .diff > 0)] | length),
    improvements: ([.comparison[] | select(.diff != null and .diff < 0)] | length),
    unchanged: ([.comparison[] | select(.diff == 0)] | length),
    missing: ([.comparison[] | select(.diff == null)] | length)
  }
' <<< "$comparison")

report=$(cat <<EOF
=== BASELINE K6 ===
$baseline_k6

=== BASELINE PROMETHEUS ===
$baseline_metrics

=== CANDIDATE K6 ===
$candidate_k6

=== CANDIDATE PROMETHEUS ===
$candidate_metrics

=== COMPARISON ===
$comparison_lines

=== TOP REGRESSIONS ===
$top_regressions

=== TOP IMPROVEMENTS ===
$top_improvements

=== LLM ANALYSIS ===
$analysis
EOF
)

mkdir -p "$(dirname "$REPORT_FILE")"
printf "%s\n" "$report" > "$REPORT_FILE"

generated_at=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
template_html=$(cat "$HTML_TEMPLATE_FILE")

summary_json_compact=$(jq -c . <<< "$summary_json")
comparison_json_compact=$(jq -c '.comparison' <<< "$comparison")
baseline_metrics_json=$(jq -c '.metrics' <<< "$baseline")
candidate_metrics_json=$(jq -c '.metrics' <<< "$candidate")
analysis_json=$(jq -Rs . <<< "$analysis")
baseline_k6_json=$(jq -Rs . <<< "$baseline_k6")
candidate_k6_json=$(jq -Rs . <<< "$candidate_k6")
baseline_metrics_text_json=$(jq -Rs . <<< "$baseline_metrics")
candidate_metrics_text_json=$(jq -Rs . <<< "$candidate_metrics")
baseline_file_json=$(jq -Rn --arg v "$BASELINE_FILE" '$v')
candidate_file_json=$(jq -Rn --arg v "$CANDIDATE_FILE" '$v')

html_report=$(jq -rRn \
  --arg template "$template_html" \
  --arg report_date "$generated_at" \
  --arg summary_json "$summary_json_compact" \
  --arg comparison_json "$comparison_json_compact" \
  --arg baseline_metrics_json "$baseline_metrics_json" \
  --arg candidate_metrics_json "$candidate_metrics_json" \
  --arg analysis_json "$analysis_json" \
  --arg baseline_k6_json "$baseline_k6_json" \
  --arg candidate_k6_json "$candidate_k6_json" \
  --arg baseline_metrics_text_json "$baseline_metrics_text_json" \
  --arg candidate_metrics_text_json "$candidate_metrics_text_json" \
  --arg baseline_file_json "$baseline_file_json" \
  --arg candidate_file_json "$candidate_file_json" \
  '
  $template
  | gsub("__REPORT_DATE__"; $report_date)
  | gsub("__SUMMARY_JSON__"; $summary_json)
  | gsub("__COMPARISON_JSON__"; $comparison_json)
  | gsub("__BASELINE_METRICS_JSON__"; $baseline_metrics_json)
  | gsub("__CANDIDATE_METRICS_JSON__"; $candidate_metrics_json)
  | gsub("__ANALYSIS_JSON__"; $analysis_json)
  | gsub("__BASELINE_K6_JSON__"; $baseline_k6_json)
  | gsub("__CANDIDATE_K6_JSON__"; $candidate_k6_json)
  | gsub("__BASELINE_METRICS_TEXT_JSON__"; $baseline_metrics_text_json)
  | gsub("__CANDIDATE_METRICS_TEXT_JSON__"; $candidate_metrics_text_json)
  | gsub("__BASELINE_FILE_JSON__"; $baseline_file_json)
  | gsub("__CANDIDATE_FILE_JSON__"; $candidate_file_json)
  ')

printf "%s\n" "$html_report" > "$HTML_REPORT_FILE"

echo "$report"
echo "HTML report saved to $HTML_REPORT_FILE"
echo "Open report: $HTML_REPORT_FILE"
cat <<'EOF'
To download the HTML report after the workflow pod has completed, use a temporary helper pod with the shared PVC:

kubectl apply -n fanout -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: fanout-report-reader
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: alpine:3.19
      command: ["sh", "-c", "sleep 600"]
      volumeMounts:
        - name: reports
          mountPath: /data
  volumes:
    - name: reports
      persistentVolumeClaim:
        claimName: fanout-metrics-pvc
YAML

kubectl cp fanout/fanout-report-reader:/data/final-report.html ./final-report.html
kubectl delete pod -n fanout fanout-report-reader
EOF
