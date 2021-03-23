#!/usr/bin/env bash

branch=${CI_COMMIT_REF_SLUG:-$(git branch | grep "\*" | cut -d\  -f2)}
commit_sha=${CI_COMMIT_SHA:-$(git rev-parse HEAD)}

get_image_tag() {
  export imagetag="${IMAGETAG:-$branch-$(date +%Y-%m-%d-%H-%M-%z |sed -e 's/+//')-$(echo "$commit_sha"|cut -c1-8)}"
}

unified_docker_build() {
  get_image_tag
  if [ -z "$BUILD_CREDENTIALS" ];then
      echo "error: BUILD_CREDENTIALS is not set to b64 encoded service account"
      exit 1
  fi

  if [ -z "$IMAGEBASE" ];then
      echo "error: IMAGEBASE is not set, please set it to something like: eu.gcr.io/something/something"
      exit 1
  fi
  if [ -z "$DOCKER_FILE" ];then
      echo "error: DOCKER_FILE is not set, please set it to the path of the Dockerfile you wish to build"
      exit 1
  fi
  if [ -z "$DOCKER_CONTEXT" ];then
      echo "error: DOCKER_CONTEXT is not set, please set it the Docker context (the root where your Dockerfile will run its commands)"
      exit 1
  fi

  echo "$BUILD_CREDENTIALS" \
    | base64 -d \
    | docker login -u _json_key --password-stdin https://"$(echo "$IMAGEBASE"|cut -f1 -d/)"
  docker pull "$IMAGEBASE:$branch" || true # to reuse some layers built earlier
  docker build "$@" --cache-from "$IMAGEBASE:$branch" \
                --cache-from "$IMAGEBASE:master" \
                -t "$IMAGEBASE:$branch" \
                -t "$IMAGEBASE:$imagetag" \
                -f "$DOCKER_FILE" "$DOCKER_CONTEXT" || \
                docker build -t "$IMAGEBASE:$branch" \
                            -t "$IMAGEBASE:$imagetag" \
                            -f "$DOCKER_FILE" "$DOCKER_CONTEXT"
}

unified_docker_push() {
  docker push "$IMAGEBASE:$branch"
  docker push "$IMAGEBASE:$imagetag"
  if [ "$branch" == "master" ]; then # so we know what is actually the latest... (in my head latest=latest stable build) although this will be only used for testing purpose, when you quickly want to spin up the "latest stable" container
    docker tag "$IMAGEBASE:$branch" "$IMAGEBASE:latest"
    docker push "$IMAGEBASE:latest"
  fi
}

gh_release() {
  local ORG=$1
  local REPO=$2
  local OUTPUT=$3

}

get_kustomize() {
  curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases \
    | grep browser_download_url \
    | grep linux \
    | cut -d '"' -f 4 \
    | grep /kustomize/v \
    | sort | tail -n 1 \
    | xargs -n 1 curl -o kustomize-dl.tgz -L && \
    tar -xzf kustomize-dl.tgz -C /bin && \
    chmod +x /bin/kustomize
}

auth_for_cluster() {
    local project=$1
    local location=$2
    local cluster=$3
    get_gcp_creds

    echo Authenticating for cluster "$project/$location/$cluster"
    if [ -n "$GITLAB_CI" ]; then
        gcloud config set project "$project"
        gcloud container clusters get-credentials "$cluster" \
            --region "$location" \
            --project "$project"
        gcloud components install kubectl --quiet
    else
        echo "Running locally, skipping authentication"
    fi
}

get_gcp_creds() {
  echo "Activating service account"
  echo "$DEPLOYMENT_CREDENTIALS" | base64 -d > "$HOME"/google-application-credentials.json
  # shellcheck disable=SC2015
  gcloud auth activate-service-account --key-file="$HOME"/google-application-credentials.json && \
    rm -f "$HOME"/google-application-credentials.json || \
    rm -f "$HOME"/google-application-credentials.json
}

# a function which is checking if our deployment was successful or not
check_status_and_auto_rollback_if_necessary() {
  # making sure, that the freshly updated deployment has the amount of healthy replicas as expected
  object_name=$1
  ns=$2
  n=0
  sleep 1 # try to wait, so the deployment actually starts
  while [ $n -ne 30 ]; do
      status_json=$(kubectl --namespace "$ns" get deployment "$object_name" -o json)
      status_replicas=$(echo "$status_json" |jq -r .status.replicas)
      while [ "$status_replicas" == "null" ]; do
          echo "Deployment is still processing, waiting 2 seconds."
          sleep 2
          status_json=$(kubectl --namespace "$ns" get deployment "$object_name" -o json)
          status_replicas=$(echo "$status_json" |jq -r .status.replicas)
      done
      status_ready_replicas=$(echo "$status_json" |jq -r .status.readyReplicas)
      status_unavailable_replicas=$(echo "$status_json" |jq -r .status.unavailableReplicas)
      status_updated_replicas=$(echo "$status_json" |jq -r .status.updatedReplicas)
      if [ "$status_ready_replicas" == "$status_replicas" ] && \
          [ "$status_updated_replicas" == "$status_replicas" ] && \
          { [ "$status_unavailable_replicas" == "0" ] || [ "$status_unavailable_replicas" == "null" ]; } then
          echo "All good."
          return
      fi
      n=$((n+1))
      echo "Deployment replica(s) is(are) not ready yet, waiting 10 seconds."
      sleep 10
  done
  echo "Times up, rolling back."
  # if the deployment replicas are not up and running after 300 seconds, just roll back to last working deployment and fail
  kubectl --namespace "$ns" rollout undo deployment "$object_name"
  exit 1
}
