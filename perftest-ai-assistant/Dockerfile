FROM grafana/k6:latest

USER root

RUN apk add --no-cache curl jq bash

WORKDIR /

COPY run_stress_collect.sh config.sh load_k6_feed.js compare_and_analyze.sh ./
COPY prompts ./prompts

RUN chmod +x run_stress_collect.sh compare_and_analyze.sh

ENTRYPOINT []

CMD ["./run_stress_collect.sh"]
