FROM google/cloud-sdk:298.0.0-alpine

COPY utils.sh /src/utils.sh
RUN source src/utils.sh \
    && get_kustomize \
    && apk add --update --no-cache jq \
    && gcloud components install kubectl --quiet \
    && gcloud components install beta --quiet
