import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../enum/enum.dart';

class ProxyTile extends ConsumerStatefulWidget {
  const ProxyTile({super.key});

  @override
  ConsumerState<ProxyTile> createState() => _ProxyInfoTileState();
}

class _ProxyInfoTileState extends ConsumerState<ProxyTile> {
  Widget _buildProxyInfoSection(
      BuildContext context, {
        required String title,
        required String proxyName,
        required String? subtitle,
        required int? delay,
        required IconData icon,
      }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: context.colorScheme.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    title,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        proxyName,
                        style: context.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (delay != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _getDelayColor(context, delay),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      delay <= 0 ? '0ms' : '${delay}ms',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: _getDelayTextColor(context, delay),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getDelayColor(BuildContext context, int delay) {
    if (delay <= 0) {
      return context.colorScheme.errorContainer;
    } else if (delay < 100) {
      return Colors.green.withOpacity(0.2);
    } else if (delay < 300) {
      return Colors.orange.withOpacity(0.2);
    } else {
      return Colors.red.withOpacity(0.2);
    }
  }

  Color _getDelayTextColor(BuildContext context, int delay) {
    if (delay <= 0) {
      return context.colorScheme.error;
    } else if (delay < 100) {
      return Colors.green.shade700;
    } else if (delay < 300) {
      return Colors.orange.shade700;
    } else {
      return Colors.red.shade700;
    }
  }

  // Helper method to safely get proxy information
  Map<String, dynamic> _getProxyInfo(WidgetRef ref) {
    try {
      final currentProfile = ref.watch(currentProfileProvider);
      final groups = ref.watch(groupsProvider);
      final currentGroupName = ref.watch(
        currentProfileProvider.select((p) => p?.currentGroupName),
      );

      if (currentProfile == null || groups.isEmpty) {
        return {'hasData': false};
      }

      final currentGroup = groups.firstWhere(
            (g) => g.name == currentGroupName,
        orElse: () => groups.first,
      );

      final selectedProxyName = ref.read(
        getSelectedProxyNameProvider(currentGroup.name),
      );

      final currentProxy = currentGroup.all.firstWhere(
            (p) => p.name == selectedProxyName,
        orElse: () => currentGroup.all.first,
      );

      final currentDelay = ref.watch(
        getDelayProvider(
          proxyName: currentProxy.name,
          testUrl: currentGroup.testUrl,
        ),
      );

      Proxy? bestProxy;
      int? bestDelay;

      for (final proxy in currentGroup.all) {
        final delay = ref.watch(
          getDelayProvider(
            proxyName: proxy.name,
            testUrl: currentGroup.testUrl,
          ),
        );

        if (delay != null && delay > 0) {
          if (bestDelay == null || delay < bestDelay) {
            bestDelay = delay;
            bestProxy = proxy;
          }
        }
      }

      return {
        'hasData': true,
        'currentProfile': currentProfile,
        'currentGroup': currentGroup,
        'currentProxy': currentProxy,
        'currentDelay': currentDelay,
        'bestProxy': bestProxy,
        'bestDelay': bestDelay,
      };
    } catch (e) {
      return {'hasData': false, 'error': e.toString()};
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(2),
      child: CommonCard(
        onPressed: () {
          globalState.appController.toPage(PageLabel.proxies);
        },
        child: Builder(
          builder: (_) {
            final proxyInfo = _getProxyInfo(ref);

            if (!proxyInfo['hasData']) {
              return Padding(
                padding: baseInfoEdgeInsets,
                child: Center(
                  child: Text(
                    appLocalizations.nullTip(appLocalizations.profile),
                    style: context.textTheme.bodySmall,
                  ),
                ),
              );
            }

            final currentProfile = proxyInfo['currentProfile'] as Profile;
            final currentGroup = proxyInfo['currentGroup'] as ProxyGroup;
            final currentProxy = proxyInfo['currentProxy'] as Proxy;
            final currentDelay = proxyInfo['currentDelay'] as int?;
            final bestProxy = proxyInfo['bestProxy'] as Proxy?;
            final bestDelay = proxyInfo['bestDelay'] as int?;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProxyInfoSection(
                    context,
                    title: "Current",
                    proxyName: currentProxy.name,
                    subtitle: currentProfile.label?.toString() ?? 'Unknown',
                    delay: currentDelay ?? 0,
                    icon: Icons.router,
                  ),
                  const SizedBox(height: 8),
                  _buildProxyInfoSection(
                    context,
                    title: "Best Ping",
                    proxyName: bestProxy?.name ?? appLocalizations.unknown,
                    subtitle: currentGroup.name,
                    delay: bestDelay,
                    icon: Icons.speed,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}