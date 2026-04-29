import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/network/images.dart';

void main() {
  test(
    'image_downloader_local_ref_never_calls_remote_getImageLoadingConfig',
    () {
      expect(
        ImageDownloader.shouldUseSourceImageConfig(localSourceKey),
        isFalse,
      );
      expect(ImageDownloader.shouldUseSourceImageConfig(null), isFalse);
      expect(
        ImageDownloader.shouldUseSourceImageConfig('Unknown:122396838'),
        isTrue,
      );
      expect(ImageDownloader.shouldUseSourceImageConfig('copymanga'), isTrue);
    },
  );
}
