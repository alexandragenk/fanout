#!/bin/bash

. config.sh

k6 run --duration $duration load_k6_feed.js

PROM="http://localhost:9090/api/v1/query"

queries=(
"sum(rate(http_request_duration_seconds_count{route='feed'}[$duration]))"
"sum(rate(http_request_duration_seconds_count{route='likes'}[$duration]))"
"histogram_quantile(0.50,sum(rate(http_request_duration_seconds_bucket{route='feed'}[$duration]))by(le))"
"histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{route='feed'}[$duration]))by(le))"
"histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket{route='feed'}[$duration]))by(le))"
"max_over_time(http_request_duration_seconds_sum{route='feed'}[$duration])/max_over_time(http_request_duration_seconds_count{route='feed'}[$duration])"
"histogram_quantile(0.50,sum(rate(http_request_duration_seconds_bucket{route='likes'}[$duration]))by(le))"
"histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{route='likes'}[$duration]))by(le))"
"histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket{route='likes'}[$duration]))by(le))"
"max_over_time(http_request_duration_seconds_sum{route='likes'}[$duration])/max_over_time(http_request_duration_seconds_count{route='likes'}[$duration])"
"(sum(rate(http_responses_group_total{route='feed',group='5xx'}[$duration])) or vector(0))/sum(rate(http_responses_group_total{route='feed'}[$duration]))"
"(sum(rate(http_responses_group_total{route='feed',group='5xx'}[$duration])) or vector(0))/sum(rate(http_responses_group_total{route='likes'}[$duration]))"
"rate(container_cpu_usage_seconds_total{name='fanout-feed-svc-1',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{name='fanout-like-svc-1',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{name='fanout-feed-db-1',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{name='fanout-like-db-1',cpu='total'}[$duration])"
"avg_over_time(container_memory_usage_bytes{name='fanout-feed-svc-1'}[$duration])"
"avg_over_time(container_memory_usage_bytes{name='fanout-like-svc-1'}[$duration])"
"avg_over_time(container_memory_usage_bytes{name='fanout-feed-db-1'}[$duration])"
"avg_over_time(container_memory_usage_bytes{name='fanout-like-db-1'}[$duration])"
"sum(rate(container_fs_reads_total{name='fanout-feed-db-1'}[$duration]))"
"sum(rate(container_fs_writes_total{name='fanout-feed-db-1'}[$duration]))"
"sum(rate(container_fs_reads_total{name='fanout-like-db-1'}[$duration]))"
"sum(rate(container_fs_writes_total{name='fanout-like-db-1'}[$duration]))"
)

result=""
for q in "${queries[@]}"; do
    value=`curl -sG "$PROM" --data-urlencode "query=$q" | jq -r '.data.result[0].value[1] // "NaN"'`
    result+="$q: $value"$'\n'
done

echo "$result"

escaped=$(printf 'Сервис лент использует сервис лайков. Проведен стресс тест. Что можешь сказать по этим метрикам?\n%s' "$result" | jq -Rs .)

echo "Analyzing..."

curl -s http://localhost:11434/api/generate -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": $escaped
}" | jq -r '.response'