FROM grafana/k6:latest

USER root

RUN apk add --no-cache curl jq bash

WORKDIR /

COPY run_stress_collect.sh compare_and_analyze.sh ./

RUN chmod +x run_stress_collect.sh compare_and_analyze.sh

ENTRYPOINT []

CMD ["bash", "-lc", "echo 'This image is intended to run only from Argo Workflow with explicit command and env.' >&2; exit 64"]
