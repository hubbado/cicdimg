# cicdimg

## Hubbado's CI/CD image

https://hub.docker.com/r/hubbado/cicdimg/

### Contents

Base of the image is `google/cloud-sdk:XYZ-alpine` and contents from base are:

- gcloud
- docker
- bash

additional contents to base are:

- kustomize (from github)
- kubectl (from gcloud components)
- gcloud beta commands (from gcloud components)
- jq (from apk)
- `utils.sh`

