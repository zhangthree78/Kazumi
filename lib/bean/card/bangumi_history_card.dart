import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:kazumi/utils/utils.dart';

// 视频历史记录卡片 - 水平布局
class BangumiHistoryCardV extends StatefulWidget {
  const BangumiHistoryCardV({
    super.key,
    required this.historyItem,
    this.sourceHistories = const [],
    this.showDelete = false,
    this.onDeleted,
    this.onSourceDeleted,
  });

  final History historyItem;
  final List<History> sourceHistories;
  final bool showDelete;
  final VoidCallback? onDeleted;
  final ValueChanged<History>? onSourceDeleted;

  @override
  State<BangumiHistoryCardV> createState() => _BangumiHistoryCardVState();
}

class _BangumiHistoryCardVState extends State<BangumiHistoryCardV> {
  final VideoPageController videoPageController =
      Modular.get<VideoPageController>();
  final PluginsController pluginsController = Modular.get<PluginsController>();
  final CollectController collectController = Modular.get<CollectController>();

  List<History> get _sourceHistories => widget.sourceHistories.isEmpty
      ? [widget.historyItem]
      : widget.sourceHistories;

  bool get _hasMultipleSources => _sourceHistories.length > 1;

  String _episodeText(History history) {
    return history.lastWatchEpisodeName.isEmpty
        ? '第${history.lastWatchEpisode}话'
        : history.lastWatchEpisodeName;
  }

  String _relativeTime(History history) {
    return Utils.formatTimestampToRelativeTime(
      history.lastWatchTime.millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<void> _onTap() async {
    if (widget.showDelete) {
      KazumiDialog.showToast(message: '编辑模式');
      return;
    }
    await _openHistory(widget.historyItem);
  }

  Future<void> _openHistory(History history) async {
    KazumiDialog.showLoading(
      msg: '获取中',
      barrierDismissible: Utils.isDesktop(),
      onDismiss: () {
        videoPageController.cancelQueryRoads();
      },
    );
    bool flag = false;
    for (Plugin plugin in pluginsController.pluginList) {
      if (plugin.name == history.adapterName) {
        videoPageController.currentPlugin = plugin;
        flag = true;
        break;
      }
    }
    if (!flag) {
      KazumiDialog.dismiss();
      KazumiDialog.showToast(message: '未找到关联番剧源');
      return;
    }
    videoPageController.bangumiItem = history.bangumiItem;
    videoPageController.title = history.bangumiItem.nameCn == ''
        ? history.bangumiItem.name
        : history.bangumiItem.nameCn;
    videoPageController.src = history.lastSrc;
    try {
      await videoPageController.queryRoads(
          history.lastSrc, videoPageController.currentPlugin.name);
      KazumiDialog.dismiss();
      Modular.to.pushNamed('/video/');
    } catch (_) {
      KazumiLogger().w("QueryManager: failed to query roads");
      KazumiDialog.dismiss();
    }
  }

  Future<bool> _confirmDelete() async {
    if (!_hasMultipleSources) {
      return true;
    }
    final result = await KazumiDialog.show<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除历史记录'),
          content: Text('确认要删除「${_title(widget.historyItem)}」的所有来源历史记录吗?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _deleteWithConfirm() async {
    if (await _confirmDelete()) {
      widget.onDeleted?.call();
    }
  }

  String _title(History history) {
    return history.bangumiItem.nameCn == ''
        ? history.bangumiItem.name
        : history.bangumiItem.nameCn;
  }

  void _deleteSourceFromSheet(BuildContext sheetContext, History history) {
    Navigator.of(sheetContext).pop();
    widget.onSourceDeleted?.call(history);
  }

  void _showSourceSheet() {
    if (!_hasMultipleSources) {
      return;
    }
    KazumiDialog.showBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    widget.showDelete ? '编辑模式' : '选择播放来源',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _sourceHistories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final history = _sourceHistories[index];
                      return ListTile(
                        leading: Icon(
                          Icons.extension_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          history.adapterName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_episodeText(history)} · ${_relativeTime(history)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: widget.showDelete
                            ? IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: colorScheme.error,
                                ),
                                tooltip: '删除此来源记录',
                                onPressed: () {
                                  _deleteSourceFromSheet(context, history);
                                },
                              )
                            : index == 0
                                ? Text(
                                    '最近',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : null,
                        onTap: () {
                          if (widget.showDelete) {
                            KazumiDialog.showToast(message: '编辑模式');
                            return;
                          }
                          Navigator.of(context).pop();
                          _openHistory(history);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double imageWidth = 80;
    final double imageHeight = 108;
    final String title = _title(widget.historyItem);
    final String episodeText = _episodeText(widget.historyItem);
    final String sourceText = _hasMultipleSources
        ? '${widget.historyItem.adapterName} · 共${_sourceHistories.length}个来源'
        : widget.historyItem.adapterName;

    return Dismissible(
      key: ValueKey(widget.historyItem.key),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) {
        widget.onDeleted?.call();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color: colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: _onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: NetworkImgLayer(
                    src: widget.historyItem.bangumiItem.images['large'] ?? '',
                    width: imageWidth,
                    height: imageHeight,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: imageHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.play_circle_outline,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                episodeText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: _hasMultipleSources ? _showSourceSheet : null,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.extension_outlined,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    sourceText,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (_hasMultipleSources) ...[
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 16,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _relativeTime(widget.historyItem),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.showDelete) ...[
                      Observer(
                        builder: (context) {
                          collectController.collectibles.length;
                          return CollectButton(
                            onClose: () {
                              FocusScope.of(context).unfocus();
                            },
                            bangumiItem: widget.historyItem.bangumiItem,
                            color: colorScheme.onSurfaceVariant,
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.open_in_new,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: '番剧详情',
                        onPressed: () {
                          Modular.to.pushNamed(
                            '/info/',
                            arguments: widget.historyItem.bangumiItem,
                          );
                        },
                      ),
                    ],
                    if (widget.showDelete)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: colorScheme.error,
                        ),
                        tooltip: '删除记录',
                        onPressed: () {
                          _deleteWithConfirm();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
