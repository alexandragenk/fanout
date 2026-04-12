#!/bin/bash

. config.sh

k6 run -e service_url=$service_url --duration $duration load_k6_feed.js

queries=(
"sum(rate(http_request_duration_seconds_count{route='feed'}[$duration]))"
"sum(rate(http_request_duration_seconds_count{route='likes'}[$duration]))"
"histogram_quantile(0.50,sum(rate(http_request_duration_seconds_bucket{route='feed'}[$duration])) by (le))"
"histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{route='feed'}[$duration])) by (le))"
"histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket{route='feed'}[$duration])) by (le))"
"max_over_time(http_request_duration_seconds_sum{route='feed'}[$duration]) / max_over_time(http_request_duration_seconds_count{route='feed'}[$duration])"
"histogram_quantile(0.50,sum(rate(http_request_duration_seconds_bucket{route='likes'}[$duration])) by (le))"
"histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{route='likes'}[$duration])) by (le))"
"histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket{route='likes'}[$duration])) by (le))"
"max_over_time(http_request_duration_seconds_sum{route='likes'}[$duration]) / max_over_time(http_request_duration_seconds_count{route='likes'}[$duration])"
"(sum(rate(http_responses_group_total{route='feed',group='5xx'}[$duration])) or vector(0)) / clamp_min(sum(rate(http_responses_group_total{route='feed'}[$duration])), 1e-9)"
"(sum(rate(http_responses_group_total{route='likes',group='5xx'}[$duration])) or vector(0)) / clamp_min(sum(rate(http_responses_group_total{route='likes'}[$duration])), 1e-9)"
"rate(container_cpu_usage_seconds_total{pod=~'feed-svc-.*',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{pod=~'like-svc-.*',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{pod=~'feed-db-.*',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{pod=~'like-db-.*',cpu='total'}[$duration])"
"avg_over_time(container_memory_working_set_bytes{pod=~'feed-svc-.*'}[$duration])"
"avg_over_time(container_memory_working_set_bytes{pod=~'like-svc-.*'}[$duration])"
"avg_over_time(container_memory_working_set_bytes{pod=~'feed-db-.*'}[$duration])"
"avg_over_time(container_memory_working_set_bytes{pod=~'like-db-.*'}[$duration])"
"sum(rate(container_fs_reads_total{pod=~'feed-db-.*'}[$duration]))"
"sum(rate(container_fs_writes_total{pod=~'feed-db-.*'}[$duration]))"
"sum(rate(container_fs_reads_total{pod=~'like-db-.*'}[$duration]))"
"sum(rate(container_fs_writes_total{pod=~'like-db-.*'}[$duration]))"
)

metrics=""
for q in "${queries[@]}"; do
    value=`curl -sG $prometheus_url/api/v1/query --data-urlencode "query=$q" | jq -r '.data.result[0].value[1] // "NaN"'`
    metrics+="$q: $value"$'\n'
done

echo "$metrics"

until curl -sf $ollama_url/api/tags | grep -q '"name"'; do
  echo "Waiting for LLM readiness.."
  sleep 1
done

echo "Analyzing..."

read -r -d '' prompt <<EOF
Проведен стресс тест сервиса лент.
Он использует сервис лайков.
Ниже метрики обоих сервисов:

$metrics

1. Найди аномалии
2. Предложи возможные причины
3. Сделай краткий вывод
EOF

curl -s $ollama_url/api/generate -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": `jq -Rs . <<<"$prompt"`
}" | jq -r '.response'