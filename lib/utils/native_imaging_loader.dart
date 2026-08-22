import 'native_imaging_loader_stub.dart'
    if (dart.library.js_interop) 'native_imaging_loader_web.dart'
    as impl;

/// Makes native_imaging's platform implementation available.
///
/// Native builds link the library into the application. Web builds fetch the
/// generated Imaging.js glue only when an image actually needs processing, so
/// it does not compete with the Flutter engine and application during startup.
Future<void> ensureNativeImagingLoaded() => impl.ensureNativeImagingLoaded();
