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
- `ConfigMap` `artifact-repositories` в namespace workflow
- опциональный in-cluster `MinIO`

Для совместимости с `argo-server`, работающим в другом namespace, endpoint S3 должен быть задан полным DNS-именем Kubernetes сервиса, например `argo-artifacts.fanout.svc.cluster.local:9000`, а не коротким `argo-artifacts:9000`.

После этого `outputs.artifacts` из workflow смогут публиковаться в Argo UI, если workflow-controller читает default artifact repository из namespace workflow.

По умолчанию как артефакты публикуются:

- промежуточные `old-report.json` и `new-report.json` из `run-assistant-collect`
- финальные `final-report.txt` и `final-report.html` из `compare-and-analyze`

Длительность нагрузочного теста задаётся одним параметром:

- `workflow.duration` в `values.yaml`

Это значение используется и для окна Prometheus-запросов, и для `k6` через переменную окружения `duration`.
