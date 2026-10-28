
import 'package:flutter/cupertino.dart';

import 'data_source_type.dart';

typedef IDataHandler = void Function(SourceType source, DataType type, dynamic data);

class DesiredDataInfo {
  List<SourceType> source;
  List<DataType> type;

  DesiredDataInfo(this.source, this.type);
}

class ISubscription {
  DesiredDataInfo info;
  IDataHandler handler;

  ISubscription(this.info, this.handler);
}

class SubscriptionManager {
  static Map<String, ISubscription> dataHandlerMap = {};

  static void subscribe(
      String handlerId,
      IDataHandler handler,
      List<SourceType> source,
      List<DataType> type,
      ) {
    // debugPrint('+++++++++++++++SubscriptionManager subscribe++++++++++++++++ $handlerId');
    // type = checkArray(type);
    // source = checkArray(source);
    final dh = dataHandlerMap[handlerId];
    if (dh != null) {
      dh.info = DesiredDataInfo(source, type);
      dh.handler = handler;
    } else {
      dataHandlerMap[handlerId] = ISubscription(
        DesiredDataInfo(source, type),
        handler,
      );
    }
  }

  static bool has(String subscriptionId) {
    return dataHandlerMap.containsKey(subscriptionId);
  }

  static List<dynamic> checkArray(dynamic data) {
    if (data is! List) {
      return [data];
    }
    return data;
  }

  static void unsubscribe(String handlerId) {
    // debugPrint('+++++++++++++++SubscriptionManager unsubscribe++++++++++++++++ $handlerId');
    dataHandlerMap.remove(handlerId);
  }

  static void publish(SourceType source, DataType type, dynamic data) {
    // debugPrint('8 ----------------------------------------------------------------------');
    if (data == null) {
      return;
    }
    // debugPrint('9 ----------------------------------------------------------------------');
    final wantedSubscriptions = getWantedSubscriptions(source, type);
    // debugPrint('10 ----------------------------------------------------------------------$dataHandlerMap');
    // for (var subscription in [wantedSubscriptions[wantedSubscriptions.length-1]]) {
    for (var subscription in wantedSubscriptions) {

      subscription.handler(source, type, data);
    }
    // debugPrint('11 ----------------------------------------------------------------------');
  }

  static List<ISubscription> getWantedSubscriptions(
      SourceType source, DataType type) {
    return dataHandlerMap.values.where((value) =>
    (value.info.source.contains(SourceType.ANY) ||
        value.info.source.contains(source)) &&
        (value.info.type.contains(DataType.ANY) ||
            value.info.type.contains(type))).toList();
  }

  static void unsubscribeAll() {
    dataHandlerMap.clear();
  }
}