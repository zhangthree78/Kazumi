import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/utils/logger.dart';

class QueryManager {
  QueryManager({
    required this.infoController,
    this.batchSize = 2,
    this.onStateChanged,
  });

  final InfoController infoController;
  final PluginsController pluginsController = Modular.get<PluginsController>();
  final int batchSize;
  final VoidCallback? onStateChanged;

  bool _isCancelled = false;
  bool _isLoading = false;
  bool _shouldNotifyState = true;
  int _nextPluginIndex = 0;
  final Set<String> _queriedPlugins = <String>{};
  final Map<String, int> _pluginRequestVersions = <String, int>{};

  bool get isLoading => _isLoading;

  bool get hasMorePluginsToLoad =>
      _nextPluginIndex < pluginsController.pluginList.length;

  void _notifyStateChanged() {
    if (!_shouldNotifyState) return;
    onStateChanged?.call();
  }

  int _nextPluginRequestVersion(String pluginName) {
    final nextVersion = (_pluginRequestVersions[pluginName] ?? 0) + 1;
    _pluginRequestVersions[pluginName] = nextVersion;
    return nextVersion;
  }

  bool _isLatestPluginRequest(String pluginName, int version) {
    return !_isCancelled && _pluginRequestVersions[pluginName] == version;
  }

  void _removeExistingResponse(String pluginName) {
    infoController.pluginSearchResponseList
        .removeWhere((response) => response.pluginName == pluginName);
  }

  List<Plugin> _takeNextBatch(int size) {
    final batch = <Plugin>[];
    while (_nextPluginIndex < pluginsController.pluginList.length &&
        batch.length < size) {
      final plugin = pluginsController.pluginList[_nextPluginIndex++];
      if (_queriedPlugins.contains(plugin.name)) continue;
      _queriedPlugins.add(plugin.name);
      batch.add(plugin);
    }
    _notifyStateChanged();
    return batch;
  }

  Future<bool> _queryPlugin(Plugin plugin, String keyword) async {
    if (_isCancelled) return false;

    final requestVersion = _nextPluginRequestVersion(plugin.name);
    _removeExistingResponse(plugin.name);
    infoController.pluginSearchStatus[plugin.name] = 'pending';

    try {
      final result = await plugin.queryBangumi(keyword, shouldRethrow: true);
      if (!_isLatestPluginRequest(plugin.name, requestVersion)) {
        return false;
      }

      infoController.pluginSearchStatus[plugin.name] = 'success';
      if (result.data.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      infoController.pluginSearchResponseList.add(result);
      return result.data.isNotEmpty;
    } catch (error) {
      if (!_isLatestPluginRequest(plugin.name, requestVersion)) {
        return false;
      }

      if (error is CaptchaRequiredException) {
        KazumiLogger()
            .w('QueryManager: captcha required for ${error.pluginName}');
        infoController.pluginSearchStatus[error.pluginName] = 'captcha';
      } else if (error is NoResultException) {
        KazumiLogger().i('QueryManager: no results for ${error.pluginName}');
        infoController.pluginSearchStatus[error.pluginName] = 'noResult';
      } else {
        final name =
            error is SearchErrorException ? error.pluginName : plugin.name;
        KazumiLogger().w('QueryManager: search error for $name');
        infoController.pluginSearchStatus[name] = 'error';
      }
      return false;
    }
  }

  Future<void> querySource(String keyword, String pluginName) async {
    for (Plugin plugin in pluginsController.pluginList) {
      if (plugin.name == pluginName) {
        _queriedPlugins.add(plugin.name);
        _notifyStateChanged();
        await _queryPlugin(plugin, keyword);
        break;
      }
    }
  }

  Future<void> queryAllSource(String keyword) async {
    _isCancelled = false;
    _nextPluginIndex = 0;
    _queriedPlugins.clear();
    _pluginRequestVersions.clear();
    infoController.pluginSearchResponseList.clear();
    infoController.pluginSearchStatus.clear();

    for (Plugin plugin in pluginsController.pluginList) {
      infoController.pluginSearchStatus[plugin.name] = 'idle';
    }

    _notifyStateChanged();
    await queryNextBatch(keyword);
  }

  Future<void> queryNextBatch(String keyword) async {
    if (_isCancelled || _isLoading) return;

    _isLoading = true;
    _notifyStateChanged();

    try {
      var batch = _takeNextBatch(batchSize);
      while (!_isCancelled && batch.isNotEmpty) {
        final results =
            await Future.wait(batch.map((plugin) => _queryPlugin(plugin, keyword)));
        if (_isCancelled) return;
        if (results.any((hasResult) => hasResult)) {
          return;
        }
        batch = _takeNextBatch(batchSize);
      }
    } finally {
      _isLoading = false;
      _notifyStateChanged();
    }
  }

  void cancel({bool notify = true}) {
    _isCancelled = true;
    _isLoading = false;
    _shouldNotifyState = notify;
    _notifyStateChanged();
  }
}
