#!/usr/bin/env bash
cd android
echo $KEYSTORE_FILE | base64 --decode --ignore-garbage > key.jks
echo "storePassword=${KEYSTORE_PASS}" >> key.properties
echo "keyPassword=${KEY_PASS}" >> key.properties
echo "keyAlias=${KEY_ALIAS}" >> key.properties
echo "storeFile=../key.jks" >> key.properties
#echo $PLAYSTORE_DEPLOY_KEY >> keys.json
ls | grep key
#bundle install
#bundle update fastlane
#bundle exec fastlane set_build_code_internal
# We don't have google play releases yet, so it's safe to comment this out
cd ..
