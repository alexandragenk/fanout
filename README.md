# Fanout AI Performance Test Assistant

Fanout — демонстрационный Kubernetes-проект для нагрузочного тестирования и AI-анализа производительности. Проект разворачивает два Go-сервиса, базы PostgreSQL, сбор метрик Prometheus через `ServiceMonitor`, запуск тестов через Argo Workflows и локальный LLM-анализ через Ollama.

Путь развёртывания: Kubernetes + Helm + Argo CD.

## Что Разворачивается

- `feed` Deployment и `feed-svc` Service на порту `8080`
- `like` Deployment и `like-svc` Service на порту `8086`
- `feed-db` и `like-db` PostgreSQL StatefulSet
- `WorkflowTemplate` `fanout-perftest-pipeline`
- Prometheus `ServiceMonitor` для сервисов
- Ollama внутри кластера
- MinIO внутри кластера как artifact repository для Argo Workflows
- bootstrap Argo CD `Application` в `argocd/fanout-application.yaml`

## Структура Репозитория

- `helm-charts/fanout` — Helm chart со всеми runtime-ресурсами Kubernetes
- `argocd/fanout-application.yaml` — Argo CD Application
- `feed` — исходный код Feed service и Dockerfile
- `like` — исходный код Like service и Dockerfile
- `perftest-ai-assistant` — k6-сценарий, сбор метрик, сравнение и генерация отчётов

## Установка С Нуля

Требования:

- работающий Kubernetes cluster minikube
- настроенный `kubectl`
- `helm`
- доступ к container registry

### 1. Создать Namespace

```bash
kubectl create namespace argocd
kubectl create namespace argoworkflow
kubectl create namespace monitoring
kubectl create namespace fanout
```

### 2. Установить Argo CD

```bash
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

Доступ к UI локально:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Начальный пароль пользователя `admin`:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### 3. Установить Argo Workflows

```bash
curl -L https://github.com/argoproj/argo-workflows/releases/latest/download/install.yaml \
  | sed 's/namespace: argo$/namespace: argoworkflow/' \
  | kubectl apply --server-side -f -
kubectl wait --for=condition=available --timeout=300s deployment/workflow-controller -n argoworkflow
kubectl wait --for=condition=available --timeout=300s deployment/argo-server -n argoworkflow
```

Для локального Minikube включите auth-mode `server`, чтобы UI Argo Workflows открывался без отдельного пользовательского токена:

```bash
kubectl patch deployment argo-server -n argoworkflow \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--auth-mode=server"}]'
kubectl rollout status deployment/argo-server -n argoworkflow
```

Доступ к UI локально:

```bash
kubectl port-forward svc/argo-server -n argoworkflow 2746:2746
```

### 4. Установить kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

Этот параметр нужен, чтобы Prometheus Operator видел `ServiceMonitor`, которые рендерит Fanout chart.

### 5. Настроить Образы И Git Source

По умолчанию используются:

- `akalashnikova7/fanout-feed:latest`
- `akalashnikova7/fanout-like:latest`
- `akalashnikova7/k6:latest`
- репозиторий `https://github.com/alexandragenk/fanout.git`
- ветка `test`

Если вы используете свой registry, branch или fork, обновите `helm-charts/fanout/values.yaml`:

- `feedService.image.repository`
- `feedService.image.tag`
- `likeService.image.repository`
- `likeService.image.tag`
- `workflow.assistantImage`
- `workflow.baselineImages.feed`
- `workflow.baselineImages.like`
- `workflow.candidateImages.feed`
- `workflow.candidateImages.like`

Если вы используете свой Git fork или branch, обновите `repoURL` и `targetRevision` в `argocd/fanout-application.yaml`.

При необходимости соберите и отправьте образы:

```bash
docker build -t k6:latest ./perftest-ai-assistant
docker build -t fanout-feed:latest ./feed
docker build -t fanout-like:latest ./like
docker push akalashnikova7/k6:latest
docker push akalashnikova7/fanout-feed:latest
docker push akalashnikova7/fanout-like:latest
```

### 6. Создать Opaque Secrets

Chart ссылается на существующие Kubernetes `Opaque` Secrets для PostgreSQL и MinIO. Создайте их до sync Argo CD приложения:

```bash
kubectl create secret generic fanout-postgres-credentials \
  --type=Opaque \
  -n fanout \
  --from-literal=password='<POSTGRES_PASSWORD>'

kubectl create secret generic argo-artifacts-credentials \
  --type=Opaque \
  -n fanout \
  --from-literal=accessKey='<MINIO_ACCESS_KEY>' \
  --from-literal=secretKey='<MINIO_SECRET_KEY>'
```

Имена Secret и ключей настраиваются в `helm-charts/fanout/values.yaml`:

- `postgres.secretName`
- `postgres.passwordKey`
- `artifactRepository.secretName`
- `artifactRepository.s3.accessKeyKey`
- `artifactRepository.s3.secretKeyKey`

### 7. Развернуть Fanout Через Argo CD

Примените bootstrap Application:

```bash
kubectl apply -n argocd -f argocd/fanout-application.yaml
```

После этого синхронизируйте приложение через Argo CD UI или через CLI:

```bash
argocd app sync fanout
```

Проверка runtime-ресурсов:

```bash
kubectl get pods -n fanout
kubectl get svc -n fanout
kubectl get workflowtemplate -n fanout
kubectl get servicemonitor -n monitoring
```

Локальная проверка Helm chart:

```bash
helm template fanout ./helm-charts/fanout -n fanout
```

## Запуск Performance Pipeline

Запустите workflow из установленного template:

```bash
argo submit -n fanout --from workflowtemplate/fanout-perftest-pipeline
```

Наблюдение за выполнением:

```bash
argo list -n fanout
argo watch -n fanout @latest
```

Pipeline выполняет шаги:

1. `deploy-main-version` — разворачивает baseline-образы
2. `wait-services` — ждёт готовности сервисов, Prometheus и Ollama
3. `run-baseline` — запускает k6 и собирает Prometheus-метрики
4. `deploy-new-version` — разворачивает candidate-образы
5. `wait-services-new`
6. `cool-down-before-candidate`
7. `run-candidate` — повторно запускает k6 и собирает метрики
8. `compare-reports` — сравнивает baseline/candidate и отправляет данные в Ollama для анализа

## Отчёты И Artifacts

Argo Workflows сохраняет artifacts в MinIO, который создаётся chart:

- `old-report.json`
- `new-report.json`
- `final-report.txt`
- `final-report.html`

JSON-отчёты содержат:

- raw `k6_output`
- временные ряды Prometheus в `metrics`
- агрегированные значения в `metrics_agg`

Финальный текстовый отчёт содержит вывод k6, сравнение Prometheus-метрик, топ регрессий, топ улучшений и интерпретацию LLM. HTML-отчёт дополнительно визуализирует собранные временные ряды.

## Сбор Метрик

Сбор метрик настраивается в `helm-charts/fanout/values.yaml`:

- `workflow.duration` управляет длительностью k6-теста и окном агрегации Prometheus
- `workflow.serviceUrl` задаёт target для k6, по умолчанию `http://feed-svc:8080`
- `workflow.prometheusUrl` указывает на kube-prometheus-stack
- `promqlQueries` задаёт список PromQL-запросов для сравнения
- `k6Script` задаёт сценарий нагрузки
- `comparisonPrompt` задаёт prompt-шаблон для LLM

Prometheus-метрики собирает `perftest-ai-assistant/run_stress_collect.sh`. Сравнение и финальный отчёт генерирует `perftest-ai-assistant/compare_and_analyze.sh`.

## Полезные Команды

```bash
kubectl logs -n fanout deploy/feed
kubectl logs -n fanout deploy/like
kubectl logs -n fanout deploy/ollama
kubectl get application -n argocd fanout
kubectl describe application -n argocd fanout
helm template fanout ./helm-charts/fanout -n fanout
```

## Примечания

- Имена Kubernetes Service сохраняют суффикс `svc`: `feed-svc` и `like-svc`.
- Workload-ресурсы, которые создают pods, не используют суффикс `svc`: pods создаются из Deployment `feed` и `like`.
- Runtime-конфигурация сервисов приходит из Helm-rendered ConfigMap.
- Argo CD — основной способ развёртывания; прямой Helm install нужен в основном для проверки и отладки.
