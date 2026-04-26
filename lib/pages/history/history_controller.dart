import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

class HistoryController = _HistoryController with _$HistoryController;

class GroupedHistory {
  const GroupedHistory({
    required this.bangumiItem,
    required this.histories,
  });

  final BangumiItem bangumiItem;
  final List<History> histories;

  History get latest => histories.first;
}

abstract class _HistoryController with Store {
  final _historyRepository = Modular.get<IHistoryRepository>();

  @observable
  ObservableList<History> histories = ObservableList<History>();

  List<GroupedHistory> get groupedHistories {
    final grouped = <int, List<History>>{};
    for (final history in histories) {
      grouped
          .putIfAbsent(history.bangumiItem.id, () => <History>[])
          .add(history);
    }

    final result = grouped.values.map((items) {
      items.sort(
        (a, b) =>
            b.lastWatchTime.millisecondsSinceEpoch -
            a.lastWatchTime.millisecondsSinceEpoch,
      );
      return GroupedHistory(
        bangumiItem: items.first.bangumiItem,
        histories: List.unmodifiable(items),
      );
    }).toList();

    result.sort(
      (a, b) =>
          b.latest.lastWatchTime.millisecondsSinceEpoch -
          a.latest.lastWatchTime.millisecondsSinceEpoch,
    );
    return result;
  }

  void init() {
    final temp = _historyRepository.getAllHistories();
    histories.clear();
    histories.addAll(temp);
  }

  Future<void> updateHistory(
      int episode,
      int road,
      String adapterName,
      BangumiItem bangumiItem,
      Duration progress,
      String lastSrc,
      String lastWatchEpisodeName) async {
    await _historyRepository.updateHistory(
      episode: episode,
      road: road,
      adapterName: adapterName,
      bangumiItem: bangumiItem,
      progress: progress,
      lastSrc: lastSrc,
      lastWatchEpisodeName: lastWatchEpisodeName,
    );
    init();
  }

  Progress? lastWatching(BangumiItem bangumiItem, String adapterName) {
    return _historyRepository.getLastWatchingProgress(bangumiItem, adapterName);
  }

  Progress? findProgress(
      BangumiItem bangumiItem, String adapterName, int episode) {
    return _historyRepository.findProgress(bangumiItem, adapterName, episode);
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> deleteGroupedHistory(GroupedHistory groupedHistory) async {
    for (final history in groupedHistory.histories) {
      await _historyRepository.deleteHistory(history);
    }
    init();
  }

  Future<void> clearProgress(
      BangumiItem bangumiItem, String adapterName, int episode) async {
    await _historyRepository.clearProgress(bangumiItem, adapterName, episode);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    histories.clear();
  }
}
