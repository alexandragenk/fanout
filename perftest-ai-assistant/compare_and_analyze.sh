#!/bin/bash
set -euo pipefail

. config.sh

BASELINE_FILE="${BASELINE_FILE:-/data/old-report.json}"
CANDIDATE_FILE="${CANDIDATE_FILE:-/data/new-report.json}"
REPORT_FILE="${REPORT_FILE:-/data/final-report.txt}"
HTML_REPORT_FILE="${HTML_REPORT_FILE:-/data/final-report.html}"
COMPARISON_PROMPT_FILE="${COMPARISON_PROMPT_FILE:-/config-prompts/comparison-prompt.txt}"

if [[ ! -f "$COMPARISON_PROMPT_FILE" && -f /prompts/comparison-prompt.txt ]]; then
  COMPARISON_PROMPT_FILE=/prompts/comparison-prompt.txt
fi

if [[ ! -f "$COMPARISON_PROMPT_FILE" ]]; then
  echo "Comparison prompt file not found: $COMPARISON_PROMPT_FILE" >&2
  exit 1
fi

html_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&#39;/g"
}

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

summary_total=$(jq -r '.total' <<< "$summary_json")
summary_regressions=$(jq -r '.regressions' <<< "$summary_json")
summary_improvements=$(jq -r '.improvements' <<< "$summary_json")
summary_unchanged=$(jq -r '.unchanged' <<< "$summary_json")
summary_missing=$(jq -r '.missing' <<< "$summary_json")
generated_at=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

comparison_rows=""
while IFS=$'\t' read -r query baseline_value candidate_value diff_value; do
  diff_class="diff-neutral"
  if [[ "$diff_value" != "null" ]]; then
    if awk "BEGIN { exit !($diff_value > 0) }"; then
      diff_class="diff-up"
    elif awk "BEGIN { exit !($diff_value < 0) }"; then
      diff_class="diff-down"
    fi
  fi

  comparison_rows+=$(cat <<EOF
<tr>
  <td><code>$(html_escape "$query")</code></td>
  <td>$(html_escape "$baseline_value")</td>
  <td>$(html_escape "$candidate_value")</td>
  <td class="$diff_class">$(html_escape "$diff_value")</td>
</tr>
EOF
)
done < <(jq -r '.comparison[] | [.query, .baseline, .candidate, (.diff|tostring)] | @tsv' <<< "$comparison")

top_regressions_rows=""
while IFS=$'\t' read -r query baseline_value candidate_value diff_value; do
  [[ -z "$query" ]] && continue
  top_regressions_rows+=$(cat <<EOF
<tr>
  <td><code>$(html_escape "$query")</code></td>
  <td>$(html_escape "$baseline_value")</td>
  <td>$(html_escape "$candidate_value")</td>
  <td class="diff-up">$(html_escape "$diff_value")</td>
</tr>
EOF
)
done < <(jq -r '.comparison | map(select(.diff != null)) | sort_by(.diff) | reverse | .[:5] | .[] | [.query, .baseline, .candidate, (.diff|tostring)] | @tsv' <<< "$comparison")

top_improvements_rows=""
while IFS=$'\t' read -r query baseline_value candidate_value diff_value; do
  [[ -z "$query" ]] && continue
  top_improvements_rows+=$(cat <<EOF
<tr>
  <td><code>$(html_escape "$query")</code></td>
  <td>$(html_escape "$baseline_value")</td>
  <td>$(html_escape "$candidate_value")</td>
  <td class="diff-down">$(html_escape "$diff_value")</td>
</tr>
EOF
)
done < <(jq -r '.comparison | map(select(.diff != null)) | sort_by(.diff) | .[:5] | .[] | [.query, .baseline, .candidate, (.diff|tostring)] | @tsv' <<< "$comparison")

html_report=$(cat <<EOF
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Fanout Comparison Report</title>
  <style>
    :root {
      --bg: #f5f1e8;
      --panel: #fffdf8;
      --ink: #1f2937;
      --muted: #6b7280;
      --line: #d6d3d1;
      --accent: #9a3412;
      --accent-soft: #ffedd5;
      --good: #166534;
      --good-soft: #dcfce7;
      --bad: #b91c1c;
      --bad-soft: #fee2e2;
      --neutral: #334155;
      --neutral-soft: #e2e8f0;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, #fde68a 0, transparent 28%),
        linear-gradient(180deg, #faf7f2 0%, var(--bg) 100%);
    }
    .page {
      max-width: 1380px;
      margin: 0 auto;
      padding: 32px 20px 56px;
    }
    .hero {
      background: linear-gradient(135deg, #fff7ed 0%, #ffffff 55%, #fef3c7 100%);
      border: 1px solid #fdba74;
      border-radius: 24px;
      padding: 28px;
      box-shadow: 0 18px 50px rgba(120, 53, 15, 0.08);
    }
    .hero h1 {
      margin: 0 0 8px;
      font-size: 32px;
      line-height: 1.1;
    }
    .hero p {
      margin: 0;
      color: var(--muted);
      font-size: 15px;
    }
    .meta {
      margin-top: 16px;
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      border-radius: 999px;
      padding: 8px 12px;
      font-size: 13px;
      background: var(--accent-soft);
      color: var(--accent);
      border: 1px solid #fdba74;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 14px;
      margin: 24px 0;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 18px;
      box-shadow: 0 10px 24px rgba(15, 23, 42, 0.04);
    }
    .card .label {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }
    .card .value {
      font-size: 28px;
      font-weight: 700;
    }
    .section {
      margin-top: 24px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 22px;
      padding: 22px;
      box-shadow: 0 10px 24px rgba(15, 23, 42, 0.04);
    }
    .section h2 {
      margin: 0 0 16px;
      font-size: 22px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 18px;
    }
    details {
      border: 1px solid var(--line);
      border-radius: 16px;
      background: #fff;
      overflow: hidden;
    }
    summary {
      cursor: pointer;
      list-style: none;
      padding: 14px 16px;
      font-weight: 600;
      background: #fafaf9;
    }
    summary::-webkit-details-marker { display: none; }
    pre {
      margin: 0;
      padding: 16px;
      overflow: auto;
      white-space: pre-wrap;
      word-break: break-word;
      font-family: "IBM Plex Mono", "SFMono-Regular", monospace;
      font-size: 12px;
      line-height: 1.55;
      background: #fff;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    th, td {
      padding: 10px 12px;
      border-bottom: 1px solid #e7e5e4;
      text-align: left;
      vertical-align: top;
    }
    th {
      background: #fafaf9;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: var(--muted);
    }
    code {
      font-family: "IBM Plex Mono", "SFMono-Regular", monospace;
      font-size: 12px;
      word-break: break-word;
    }
    .diff-up {
      color: var(--bad);
      background: var(--bad-soft);
      font-weight: 700;
    }
    .diff-down {
      color: var(--good);
      background: var(--good-soft);
      font-weight: 700;
    }
    .diff-neutral {
      color: var(--neutral);
      background: var(--neutral-soft);
      font-weight: 700;
    }
    .analysis {
      white-space: pre-wrap;
      line-height: 1.65;
      font-size: 14px;
    }
    @media (max-width: 980px) {
      .grid { grid-template-columns: 1fr; }
      .hero h1 { font-size: 26px; }
    }
  </style>
</head>
<body>
  <div class="page">
    <section class="hero">
      <h1>Fanout Performance Comparison</h1>
      <p>Сравнение baseline и candidate по k6, Prometheus и итоговому LLM-анализу.</p>
      <div class="meta">
        <span class="badge">Generated: $(html_escape "$generated_at")</span>
        <span class="badge">Baseline file: $(html_escape "$BASELINE_FILE")</span>
        <span class="badge">Candidate file: $(html_escape "$CANDIDATE_FILE")</span>
      </div>
    </section>

    <section class="summary">
      <div class="card"><div class="label">Total metrics</div><div class="value">$(html_escape "$summary_total")</div></div>
      <div class="card"><div class="label">Regressions</div><div class="value">$(html_escape "$summary_regressions")</div></div>
      <div class="card"><div class="label">Improvements</div><div class="value">$(html_escape "$summary_improvements")</div></div>
      <div class="card"><div class="label">Unchanged</div><div class="value">$(html_escape "$summary_unchanged")</div></div>
      <div class="card"><div class="label">Missing diff</div><div class="value">$(html_escape "$summary_missing")</div></div>
    </section>

    <section class="section">
      <h2>Metric Comparison</h2>
      <table>
        <thead>
          <tr>
            <th>Query</th>
            <th>Baseline</th>
            <th>Candidate</th>
            <th>Diff</th>
          </tr>
        </thead>
        <tbody>
          $comparison_rows
        </tbody>
      </table>
    </section>

    <section class="section">
      <h2>Top Changes</h2>
      <div class="grid">
        <div>
          <h3>Top Regressions</h3>
          <table>
            <thead>
              <tr>
                <th>Query</th>
                <th>Baseline</th>
                <th>Candidate</th>
                <th>Diff</th>
              </tr>
            </thead>
            <tbody>
              $top_regressions_rows
            </tbody>
          </table>
        </div>
        <div>
          <h3>Top Improvements</h3>
          <table>
            <thead>
              <tr>
                <th>Query</th>
                <th>Baseline</th>
                <th>Candidate</th>
                <th>Diff</th>
              </tr>
            </thead>
            <tbody>
              $top_improvements_rows
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <section class="section">
      <h2>LLM Analysis</h2>
      <div class="analysis">$(html_escape "$analysis")</div>
    </section>

    <section class="section">
      <h2>Run Details</h2>
      <div class="grid">
        <details>
          <summary>Baseline k6 output</summary>
          <pre>$(html_escape "$baseline_k6")</pre>
        </details>
        <details>
          <summary>Candidate k6 output</summary>
          <pre>$(html_escape "$candidate_k6")</pre>
        </details>
        <details>
          <summary>Baseline Prometheus metrics</summary>
          <pre>$(html_escape "$baseline_metrics")</pre>
        </details>
        <details>
          <summary>Candidate Prometheus metrics</summary>
          <pre>$(html_escape "$candidate_metrics")</pre>
        </details>
      </div>
    </section>
  </div>
</body>
</html>
EOF
)

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
