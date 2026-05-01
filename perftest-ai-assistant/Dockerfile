FROM grafana/k6:latest

USER root

RUN apk add --no-cache curl jq bash

WORKDIR /

ENTRYPOINT []

CMD ["bash", "-lc", "echo 'This image is intended to run only from Argo Workflow with explicit command and env.' >&2; exit 64"]
