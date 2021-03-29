FROM google/cloud-sdk:300.0.0-alpine

RUN apk add --update --no-cache jq
RUN gcloud components install kubectl --quiet
RUN gcloud components install beta --quiet
COPY utils.sh /src/utils.sh
COPY setup.sh /src/setup.sh
RUN source src/setup.sh && get_kustomize
