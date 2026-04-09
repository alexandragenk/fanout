FROM grafana/k6:latest

USER root

RUN apk add --no-cache curl jq bash

WORKDIR /app

COPY run_stress.sh config.sh load_k6_feed.js ./

RUN chmod +x run_stress.sh

ENTRYPOINT []

CMD ["./run_stress.sh"]
