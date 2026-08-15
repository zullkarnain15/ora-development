import 'dart:io';

Future<bool> defaultReachabilityProbe() async {
  final addresses = await InternetAddress.lookup('script.google.com');
  return addresses.isNotEmpty &&
      addresses.any((address) => address.rawAddress.isNotEmpty);
}
