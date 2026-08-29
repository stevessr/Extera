#!/bin/sh -ve
flutter pub upgrade --major-versions
flutter pub get
dart fix --apply
dart run tidy_imports --no-comments
dart format lib test
