#!/bin/bash

. config.sh

queries=(
"sum(rate(http_request_duration_ms_count{route='feed'}[$duration]))"
"sum(rate(http_request_duration_ms_count{route='likes'}[$duration]))"
"histogram_quantile(0.50,sum(rate(http_request_duration_ms_bucket{route='feed'}[$duration]))by(le))"
"histogram_quantile(0.95,sum(rate(http_request_duration_ms_bucket{route='feed'}[$duration]))by(le))"
"histogram_quantile(0.99,sum(rate(http_request_duration_ms_bucket{route='feed'}[$duration]))by(le))"
"((sum(rate(http_request_duration_ms_sum{route='feed'}[$duration]))/sum(rate(http_request_duration_ms_count{route='feed'}[$duration])))>=0)"
"histogram_quantile(0.50,sum(rate(http_request_duration_ms_bucket{route='likes'}[$duration]))by(le))"
"histogram_quantile(0.95,sum(rate(http_request_duration_ms_bucket{route='likes'}[$duration]))by(le))"
"histogram_quantile(0.99,sum(rate(http_request_duration_ms_bucket{route='likes'}[$duration]))by(le))"
"((sum(rate(http_request_duration_ms_sum{route='likes'}[$duration]))/sum(rate(http_request_duration_ms_count{route='likes'}[$duration])))>=0)"
"(100*(sum(rate(http_responses_group_total{route='feed',group='5xx'}[$duration]))/sum(rate(http_responses_group_total{route='feed'}[$duration])))>=0)"
"(100*(sum(rate(http_responses_group_total{route='likes',group='5xx'}[$duration]))/sum(rate(http_responses_group_total{route='likes'}[$duration])))>=0)"
"sum(rate(container_fs_reads_total{name='fanout-feed-db-1'}[$duration]))"
"sum(rate(container_fs_writes_total{name='fanout-feed-db-1'}[$duration]))"
"sum(rate(container_fs_reads_total{name='fanout-like-db-1'}[$duration]))"
"sum(rate(container_fs_writes_total{name='fanout-like-db-1'}[$duration]))"
"(container_memory_usage_bytes{name='fanout-feed-svc-1'}/1048576)"
"(container_memory_usage_bytes{name='fanout-like-svc-1'}/1048576)"
"(container_memory_usage_bytes{name='fanout-feed-db-1'}/1048576)"
"(container_memory_usage_bytes{name='fanout-like-db-1'}/1048576)"
"rate(container_cpu_usage_seconds_total{name='fanout-feed-svc-1',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{name='fanout-like-svc-1',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{name='fanout-feed-db-1',cpu='total'}[$duration])"
"rate(container_cpu_usage_seconds_total{name='fanout-like-db-1',cpu='total'}[$duration])"
)

prom_query () {
  curl -sG "$prometheus_url/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] | try (tonumber | (. * 100 | round / 100)) catch "NaN"'
}

prom_query_range () {
  curl -sG "$prometheus_url/api/v1/query_range?start=$start&end=$end&step=15" --data-urlencode "query=$1" | jq -c '.data.result[0].values // []'
}

export date=`date -u`
fname=`date -u +"report_%Y-%m-%d_%H-%M-%S.html"`

start=$(date +%s)
k6 run -e service_url=$service_url --duration $duration load_k6_feed.js
end=$(date +%s)

metrics_agg=""
for q in "${queries[@]}"; do
  q_max="max_over_time($q[$duration:])"
  metrics_agg+="$q_max: $(prom_query $q_max)"$'\n'
  q_avg="avg_over_time($q[$duration:])"
  metrics_agg+="$q_avg: $(prom_query $q_avg)"$'\n'
done

export metrix="{"$'\n'
for q in "${queries[@]}"; do
  metrix+="\"$q\": $(prom_query_range $q),"$'\n'
done
metrix+="}"

until curl -sf $ollama_url/api/tags | grep -q '"name"'; do
  echo "Waiting for LLM readiness.."
  sleep 1
done

echo "Analyzing..."

read -r -d '' prompt <<EOF
Проведен стресс тест сервиса лент.
Он использует сервис лайков.
Ниже метрики обоих сервисов:

$metrics_agg

1. Найди аномалии
2. Предложи возможные причины
3. Сделай краткий вывод
EOF

echo "$prompt"

start=`date +%s`
export analysis=$(curl -s $ollama_url/api/generate -d "{
  \"model\": \"default\",
  \"stream\": false,
  \"prompt\": $(jq -Rs . <<<"$prompt")
}" | jq '.response')

echo "$analysis" | jq -r

dur=$((`date +%s`-start))

mb=$(prom_query "max_over_time(container_memory_working_set_bytes{name='ollama'}[${dur}s])/1048576")

echo "Анализ занял времени $durс, памяти $mb мб."

envsubst < template.html > $fname