# Fanout в Kubernetes + Argo Workflows

В каталоге `k8s/` теперь есть раздельные манифесты, а `fanout-all-in-one.yaml` оставлен только как legacy reference. Для новых развёртываний его больше не используем.

Также рядом добавлен Helm chart в [charts/fanout](/home/alexandra/Desktop/fanout/charts/fanout). Это основной источник манифестов для Argo CD UI: `Application` должен смотреть именно на chart, а не на каталог `k8s/`.

Ниже — минимальный рабочий набор манифестов для переноса репозитория `alexandragenk/fanout` в Kubernetes и запуска нагрузочного теста через Argo Workflows.

## Что учтено из репозитория

- В проекте есть два сервиса: `feed_svc` и `like_svc`, каждый со своей PostgreSQL базой. В `docker-compose.yaml` также поднимаются `prometheus`, `cadvisor` и `ollama`.
- В `feed_svc_cfg.yaml` приложение слушает `:8080`, обращается к БД `feed-db:5432` и к сервису лайков по URL `http://like-svc:8086`.
- В `like_svc_cfg.yaml` сервис лайков слушает `:8086` и использует БД `like-db:5432`.
- В `prometheus.yml` настроены scrape targets для `feed-svc:8080`, `like-svc:8086` и `cadvisor:8080`.
- В `perftest-ai-assistant/load_k6_feed.js` тест вызывает `GET /feed` и передаёт заголовок `X-User-Id`.
- В `perftest-ai-assistant/config.sh` и `run_stress_collect.sh` используются параметры окружения и cluster-local адреса, поэтому сценарий работает внутри Kubernetes без отдельного локального stress-runner.

## Важные допущения

1. Для Kubernetes нужны контейнерные образы, доступные из кластера. Поэтому перед применением манифестов нужно собрать и запушить:
   - `<REGISTRY>/fanout-feed-svc:<TAG>`
   - `<REGISTRY>/fanout-like-svc:<TAG>`
2. В исходном репозитории `fill_data.sh` работает через `localhost:8080`; для кластера в workflow используется отдельный seed-step, который вызывает тот же API внутри namespace.
3. Для простоты используется `emptyDir` для Prometheus. Для постоянного хранения метрик его лучше заменить на PVC.
4. Ollama оставлен в кластере как отдельный Deployment. Для полноценной модели на CPU/GPU могут понадобиться другие ресурсы.
5. В Dockerfile `feed_svc` указан `EXPOSE 8086`, но конфигурация сервиса задаёт `run_address: ":8080"`, поэтому в Kubernetes сервис опубликован на 8080.

## Структура файлов

Применяйте в таком порядке:

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-configmaps.yaml
kubectl apply -f 02-postgres.yaml
kubectl apply -f 03-apps.yaml
kubectl apply -f 04-observability.yaml
kubectl apply -f 05-argo-workflow.yaml
```

Для Argo CD используйте отдельный манифест [argocd/fanout-application.yaml](/home/alexandra/Desktop/fanout/argocd/fanout-application.yaml):

```bash
kubectl apply -n argocd -f ../argocd/fanout-application.yaml
```

## 1. Сборка и публикация образов

Из корня репозитория:

```bash
docker build -t <REGISTRY>/fanout-feed-svc:<TAG> ./feed_svc
docker build -t <REGISTRY>/fanout-like-svc:<TAG> ./like_svc

docker push <REGISTRY>/fanout-feed-svc:<TAG>
docker push <REGISTRY>/fanout-like-svc:<TAG>
```

Потом откройте файл `03-apps.yaml` и при необходимости замените текущие `image` у `feed-svc` и `like-svc` на свои реальные имена образов и теги.

## 2. Подготовка Argo Workflows

Если Argo Workflows ещё не установлен:

```bash
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/latest/download/install.yaml
```

Проверьте, что контроллер и сервер поднялись:

```bash
kubectl get pods -n argo
```

## 3. Развёртывание приложения

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-configmaps.yaml
kubectl apply -f 02-postgres.yaml
kubectl apply -f 03-apps.yaml
kubectl apply -f 04-observability.yaml
```

Проверка:

```bash
kubectl get pods -n fanout
kubectl get svc -n fanout
kubectl logs -n fanout deploy/feed-svc
kubectl logs -n fanout deploy/like-svc
```

Если вы используете Argo CD, проверьте [argocd/fanout-application.yaml](/home/alexandra/Desktop/fanout/argocd/fanout-application.yaml): сейчас там указаны `repoURL: https://github.com/alexandragenk/fanout.git`, `targetRevision: test`, `path: charts/fanout`. Это значит, что Argo CD UI и все runtime-ресурсы, включая `WorkflowTemplate`, должны приходить из Helm chart. Если у вас fork, другой remote или другая ветка, замените эти значения на свои. Сам объект `Application` должен жить в namespace `argocd`, тогда он будет виден в UI Argo CD, даже если целевой namespace развёртывания приложения — `fanout`.

## 4. Запуск workflow

```bash
argo submit -n fanout --from workflowtemplate/fanout-perftest-pipeline --watch
```

При использовании Argo CD отдельно применять `WorkflowTemplate` не нужно: он уже должен быть создан из chart `charts/fanout`. Достаточно дождаться sync приложения `fanout`, а затем запускать `argo submit`.

## 5. Что делает workflow

Workflow состоит из шагов:

1. `seed-data` — наполняет систему начальными данными через HTTP API `feed-svc`.
2. `run-k6` — выполняет k6-сценарий по `/feed`.
3. `collect-metrics` — забирает значения из Prometheus API.
4. `analyze-with-ollama` — отправляет собранные метрики в Ollama и получает текстовый отчёт.

Набор PromQL-запросов для шага сбора метрик вынесен в `ConfigMap` `promql-queries-config`, k6-сценарий в `ConfigMap` `k6-scripts-config`, а LLM-prompts в `ConfigMap` `llm-prompts-config` в [01-configmaps.yaml](/home/alexandra/Desktop/fanout/k8s/01-configmaps.yaml). Чтобы поменять состав метрик, сам нагрузочный сценарий или формулировку анализа, достаточно обновить `data.queries.txt`, `data.load_k6_feed.js`, `data.analysis-prompt.txt` или `data.comparison-prompt.txt` и заново применить `01-configmaps.yaml` без пересборки образа `perftest-ai-assistant`.

## 6. Как посмотреть результаты

Последний шаг пишет отчёт в stdout:

```bash
argo logs -n fanout @latest
```

Можно посмотреть и по pod'у:

```bash
kubectl logs -n fanout <workflow-pod-name>
```

Встроенный artifact repository в chart включён по умолчанию. Если он успешно поднимется и workflow-controller подхватит default artifact repository из namespace `fanout`, шаги workflow будут публиковать артефакты.

Шаг `compare-and-analyze` публикует:

- `final-report-text`
- `final-report-html`

как `outputs.artifacts`. Тогда их можно открывать прямо из UI Argo Workflows на ноде сравнения без временного helper pod.

Шаги `run-baseline` и `run-candidate` также публикуют промежуточные JSON-отчёты как artifacts из `run-assistant-collect`.

## 7. Что я бы улучшил дальше

- заменить `emptyDir` у Prometheus на PVC;
- добавить Ingress для Prometheus и сервисов;
- вынести SQL-инициализацию / seed в отдельный Job или миграционный контейнер;
- вместо cAdvisor DaemonSet перейти на kubelet/cAdvisor scrape через ServiceMonitor, если в кластере уже есть Prometheus Operator;
- собрать отдельный образ для `perftest-ai-assistant`, чтобы не держать длинные shell-скрипты в ConfigMap.
