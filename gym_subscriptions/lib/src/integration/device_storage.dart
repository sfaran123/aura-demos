// Where sign-in and gym data are kept between runs: files on a device,
// the browser's localStorage on the web.
export 'device_storage_io.dart' if (dart.library.js_interop) 'device_storage_web.dart';
