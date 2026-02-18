import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../offline/hive_boxes.dart';

class TrackingQueue {
  TrackingQueue(this._box);

  final Box<Map> _box;
  final _uuid = const Uuid();

  Future<void> enqueue(Map<String, dynamic> payload) async {
    final id = _uuid.v4();
    await _box.put(id, payload);
  }

  Future<List<Map<String, dynamic>>> drain() async {
    final items = _box.values.map((e) => Map<String, dynamic>.from(e)).toList();
    await _box.clear();
    return items;
  }

  int get count => _box.length;
}

final trackingQueueProvider = Provider<TrackingQueue>((ref) {
  final box = Hive.box<Map>(HiveBoxes.trackingPings);
  return TrackingQueue(box);
});
