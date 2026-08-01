# Extera Next AppImage

Extera Next is provided as an AppImage too.

## Building

- Ensure you install `appimagetool`

```shell
flutter build linux --release

# assemble Extera.AppDir and run appimagetool
./scripts/build-appimage.sh          # or: ./scripts/build-appimage.sh arm64
```

The result lands in `appimage/Extera_Next-<arch>.AppImage`.
