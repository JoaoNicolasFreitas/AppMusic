import 'package:flutter/services.dart';

class MediaDeletionService {
  static const _channel = MethodChannel('appmusic/media_deletion');

  Future<bool> delete(int mediaId) async {
    final deleted = await _channel.invokeMethod<bool>('deleteAudio', {
      'id': mediaId,
    });
    return deleted ?? false;
  }
}
