# Fanout Helm Chart

Установка:

```bash
helm install fanout ./charts/fanout -n fanout --create-namespace
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
