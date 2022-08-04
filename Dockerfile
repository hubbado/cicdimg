FROM google/cloud-sdk:395.0.0-alpine

RUN apk add --update --no-cache jq
RUN gcloud components install kubectl --quiet
COPY utils.sh /src/utils.sh
COPY setup.sh /src/setup.sh
RUN source src/setup.sh && get_kustomize
