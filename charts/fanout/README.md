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
