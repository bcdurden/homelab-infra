#!/bin/bash

TAR_FILE=$1
TKG_CUSTOM_IMAGE_REPOSITORY=${TKG_CUSTOM_IMAGE_REPOSITORY:-''}
if [ -n "$TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE" ]; then
  echo $TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE > /tmp/cacrtbase64
  base64 -d /tmp/cacrtbase64 > /tmp/cacrtbase64d.crt
fi

TMP_DIR=$(mktemp -d /tmp/tkg_images.XXXX)
tar xvf $TAR_FILE -C $TMP_DIR/
pushd $TMP_DIR
  # for every tar file
  for f in *.tar ; do
      IMAGE_FILE=$(echo $f | tr % /)
      FULL_IMAGE="${IMAGE_FILE%.*}"
      IMAGE=$(echo "$FULL_IMAGE" | cut -f1 -d":")
      imgpkg copy --tar $f --to-repo ${TKG_CUSTOM_IMAGE_REPOSITORY}/${IMAGE} --registry-ca-cert-path /tmp/cacrtbase64d.crt
  done

popd
rm -rf $TMP_DIR