#!/bin/bash
set -euo pipefail

. config.sh

BASELINE_FILE="${BASELINE_FILE:-/data/old-report.json}"
CANDIDATE_FILE="${CANDIDATE_FILE:-/data/new-report.json}"
REPORT_FILE="${REPORT_FILE:-/data/final-report.txt}"
COMPARISON_PROMPT_FILE="${COMPARISON_PROMPT_FILE:-/config-prompts/comparison-prompt.txt}"

if [[ ! -f "$COMPARISON_PROMPT_FILE" && -f /prompts/comparison-prompt.txt ]]; then
  COMPARISON_PROMPT_FILE=/prompts/comparison-prompt.txt
fi

if [[ ! -f "$COMPARISON_PROMPT_FILE" ]]; then
  echo "Comparison prompt file not found: $COMPARISON_PROMPT_FILE" >&2
  exit 1
fi

baseline=$(cat "$BASELINE_FILE")
candidate=$(cat "$CANDIDATE_FILE")

comparison=$(jq -n \
  --argjson baseline "$baseline" \
  --argjson candidate "$candidate" \
  '
  {
    baseline_metrics_count: ($baseline.prometheus_metrics | length),
    candidate_metrics_count: ($candidate.prometheus_metrics | length),
    comparison: [
      $baseline.prometheus_metrics
      | keys[]
      | . as $key
      | {
          query: $key,
          baseline: ($baseline.prometheus_metrics[$key]),
          candidate: ($candidate.prometheus_metrics[$key]),
          diff: (
            (($candidate.prometheus_metrics[$key] | tonumber?) // null)
            -
            (($baseline.prometheus_metrics[$key] | tonumber?) // null)
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
  .prometheus_metrics
  | to_entries
  | map("\(.key): \(.value)")
  | join("\n")
' <<< "$baseline")
candidate_metrics=$(jq -r '
  .prometheus_metrics
  | to_entries
  | map("\(.key): \(.value)")
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

echo "$report"
