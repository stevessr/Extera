import 'package:timezone/data/latest_10y.dart' as timezone_data;

/// The UI only converts the current instant while displaying and publishing
/// profile timezones. The rolling ten-year database covers that use while
/// compiling to roughly a quarter of the full database's input size.
void initializeTimeZones() => timezone_data.initializeTimeZones();
