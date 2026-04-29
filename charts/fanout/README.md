# Fanout Helm Chart

Установка:

```bash
helm install fanout ./charts/fanout -n fanout --create-namespace
```

Argo CD `Application` вынесен отдельно:

```bash
kubectl apply -n argocd -f ./argocd/fanout-application.yaml
```

Проверка:

```bash
helm template fanout ./charts/fanout -n fanout
```

Основные параметры настраиваются через `values.yaml`:

- `feedService.image.*`
- `likeService.image.*`
- `workflow.*`
- `artifactRepository.*`
- `promqlQueries`
- `k6Script`
- `analysisPrompt`
- `comparisonPrompt`
- `argocdApplication.*`

`Argo CD Application` по умолчанию выключен:

```yaml
argocdApplication:
  enabled: false
```

Рекомендуемая схема:

- chart `charts/fanout` управляет runtime-ресурсами;
- отдельный файл [argocd/fanout-application.yaml](/home/alexandra/Desktop/fanout/argocd/fanout-application.yaml) создаёт объект `Application` в `argocd`;
- `k8s/fanout-all-in-one.yaml` остаётся только как legacy reference и не используется для новых deploy.

Встроенный artifact repository для Argo Workflows включён по умолчанию. Chart создаст:

- `Secret` с access/secret key
- `ConfigMap` `artifact-repositories` в namespace релиза, по умолчанию `fanout`
- опциональный in-cluster `MinIO`

Для совместимости с `argo-server`, работающим в другом namespace, endpoint S3 должен быть задан полным DNS-именем Kubernetes сервиса, например `argo-artifacts.fanout.svc.cluster.local:9000`, а не коротким `argo-artifacts:9000`.

`WorkflowTemplate` также явно ссылается на этот `artifact-repositories/default-v1`, поэтому артефакты должны публиковаться именно в репозиторий, созданный этим chart, а не в внешний default repo `workflow-controller`.

По умолчанию как артефакты публикуются:

- промежуточные `old-report.json` и `new-report.json` из `run-assistant-collect`
- финальные `final-report.txt` и `final-report.html` из `compare-and-analyze`

Длительность нагрузочного теста задаётся одним параметром:

- `workflow.duration` в `values.yaml`

Это значение используется и для окна Prometheus-запросов, и для `k6` через переменную окружения `duration`.

## Как снимаются и используются метрики

Pipeline в `WorkflowTemplate` работает в два основных этапа:

- `run-assistant-collect` выполняется дважды: для `baseline` и для `candidate`
- `compare-and-analyze` читает оба отчёта, сравнивает их и строит финальный текстовый и HTML-отчёт

### Источники метрик

Используются два источника:

- `k6` для нагрузочного прогона HTTP-сценария
- `Prometheus` для снятия метрик приложения, баз данных и контейнеров

Набор PromQL-запросов задаётся в `values.yaml` через `promqlQueries`.
Сценарий нагрузки `k6` задаётся через `k6Script`.

### Как работает сбор

Шаг `run-assistant-collect` запускает скрипт [perftest-ai-assistant/run_stress_collect.sh](/home/alexandra/Desktop/fanout/perftest-ai-assistant/run_stress_collect.sh).

Во время этого шага:

1. Запускается `k6 run` против `workflow.serviceUrl`.
2. Весь текстовый вывод `k6` сохраняется как строка `k6_output`.
3. Фиксируются `start` и `end` в Unix time.
4. Для каждого запроса из `promqlQueries` выполняются запросы в Prometheus.

Для каждого PromQL-выражения снимаются два представления:

- `query_range` за весь интервал нагрузки с шагом `15` секунд
- агрегаты `avg_over_time((query)[duration:])` и `max_over_time((query)[duration:])`

Если Prometheus возвращает `NaN` или пустое значение, оно нормализуется в `null`.
Числовые значения округляются до двух знаков после запятой.

### Что попадает в промежуточные отчёты

Каждый запуск `run-assistant-collect` формирует JSON-файл:

- `old-report.json` для `baseline`
- `new-report.json` для `candidate`

Структура отчёта:

```json
{
  "k6_output": "...",
  "metrics": {
    "PROMQL_QUERY": [[timestamp, value], ...]
  },
  "metrics_agg": {
    "PROMQL_QUERY": {
      "max": 123.45,
      "avg": 67.89
    }
  }
}
```

Поле `metrics` хранит полный временной ряд по каждому запросу.
Поле `metrics_agg` хранит агрегаты, которые потом используются как основной источник для сравнения baseline и candidate.

### Как используется сравнение

Шаг `compare-and-analyze` запускает скрипт [perftest-ai-assistant/compare_and_analyze.sh](/home/alexandra/Desktop/fanout/perftest-ai-assistant/compare_and_analyze.sh).

Скрипт:

1. Читает `old-report.json` и `new-report.json`.
2. Для каждого запроса из `metrics_agg` берёт `avg` baseline и `avg` candidate.
3. Считает `diff = candidate_avg - baseline_avg`.
4. Строит список всех сравнений, топ-5 регрессий и топ-5 улучшений.

Сравнение сейчас строится именно по средним значениям `avg`.
Временные ряды из `metrics` сохраняются для HTML-отчёта и визуализации, но не являются основной численной базой для diff.

### Как используется LLM-анализ

После численного сравнения формируется prompt для `ollama`.
В prompt подставляются:

- полный текстовый вывод `k6` для baseline
- полный текстовый вывод `k6` для candidate
- все строки сравнения Prometheus-метрик
- топ регрессий
- топ улучшений

LLM не собирает метрики сам и не вычисляет diff.
Он получает уже подготовленные численные данные и пишет интерпретацию результатов.

### Какие файлы появляются на выходе

В результате pipeline появляются:

- промежуточные `old-report.json` и `new-report.json`
- финальный текстовый отчёт `final-report.txt`
- финальный HTML-отчёт `final-report.html`

Финальный текстовый отчёт содержит:

- вывод `k6` для baseline
- агрегированные Prometheus-метрики для baseline
- вывод `k6` для candidate
- агрегированные Prometheus-метрики для candidate
- полное сравнение по всем запросам
- топ регрессий и улучшений
- текстовый вывод LLM

HTML-отчёт дополнительно использует:

- `summary_json` с количеством регрессий, улучшений, неизменившихся и отсутствующих метрик
- `comparison_json` со всеми diff
- `baseline.metrics` и `candidate.metrics` с временными рядами

### Какие параметры влияют на метрики

Основные настройки находятся в `values.yaml`:

- `workflow.duration` задаёт и длительность нагрузки, и окно Prometheus-агрегации
- `workflow.serviceUrl` задаёт target для `k6`
- `workflow.prometheusUrl` задаёт endpoint Prometheus
- `promqlQueries` задаёт список снимаемых метрик
- `k6Script` задаёт сценарий нагрузки
- `analysisPrompt` и `comparisonPrompt` задают шаблоны текста для LLM

### Практический смысл полей

Если нужно анализировать форму графика, выбросы или поведение во времени, смотри `metrics`.
Если нужно сравнивать baseline и candidate численно, смотри `metrics_agg`.
Если нужен краткий человекочитаемый вывод, смотри `final-report.txt` и `final-report.html`.
