import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';
import 'package:lichess_mobile/src/model/game/live_assistance_controller.dart';
import 'package:lichess_mobile/src/styles/styles.dart';

class const LiveEvaluationHeader({
  required final GameFullId gameId,
  required final Side orientation,
  final double? width,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for live moves in the game
    ref.listen(gameControllerProvider(gameId), (_, next) {
      final state = next.value;
      if (state != null && state.game.playable) {
        ref
            .read(liveAssistanceProvider(gameId).notifier)
            .onPositionChanged(
              variant: state.game.meta.variant,
              initialPosition: state.game.initialPosition,
              currentPosition: state.currentPosition,
            );
      }
    });

    // Initial position evaluation trigger
    final currentGameState = ref.watch(gameControllerProvider(gameId)).value;
    if (currentGameState != null && currentGameState.game.playable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref
              .read(liveAssistanceProvider(gameId).notifier)
              .onPositionChanged(
                variant: currentGameState.game.meta.variant,
                initialPosition: currentGameState.game.initialPosition,
                currentPosition: currentGameState.currentPosition,
              );
        }
      });
    }

    try {
      final assistance = ref.watch(liveAssistanceProvider(gameId));

      if (!assistance.enabled) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

      final whiteChances = assistance.whiteWinningChances ?? 0.0;
      // Normalized winning chance from 0.0 (all black) to 1.0 (all white)
      final double rawWhiteFraction = ((whiteChances + 1.0) / 2.0).clamp(0.03, 0.97);

      // If orientation is Black at bottom, mirror the bar so left side matches Black
      final double leftFraction = orientation == Side.white
          ? rawWhiteFraction
          : (1.0 - rawWhiteFraction);

      final leftColor = orientation == Side.white ? Colors.white : const Color(0xFF262421);
      final rightColor = orientation == Side.white ? const Color(0xFF262421) : Colors.white;

      final suggestions = assistance.suggestions;

      return Container(
        width: width,
        margin: const EdgeInsets.only(bottom: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            // 1. Move Suggestions Row
            SizedBox(
              height: 28.0,
              child: Row(
                children: [
                  Expanded(
                    child: suggestions.isEmpty
                        ? Align(
                            alignment: .centerLeft,
                            child: Text(
                              assistance.isComputing ? 'Calculating best moves...' : '',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: textShade(context, 0.6),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: .horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: suggestions.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6.0),
                            itemBuilder: (context, index) {
                              final suggestion = suggestions[index];
                              final isBest = index == 0;

                              final isWhiteAdvantage = !suggestion.evalString.startsWith('-');
                              final scoreColor = isWhiteAdvantage
                                  ? (isDark ? Colors.greenAccent.shade200 : Colors.green.shade800)
                                  : (isDark
                                        ? Colors.orangeAccent.shade200
                                        : Colors.deepOrange.shade800);

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: isBest
                                      ? (isDark
                                            ? theme.colorScheme.primaryContainer.withValues(
                                                alpha: 0.4,
                                              )
                                            : theme.colorScheme.primaryContainer.withValues(
                                                alpha: 0.6,
                                              ))
                                      : (isDark
                                            ? Colors.white.withValues(alpha: 0.08)
                                            : Colors.black.withValues(alpha: 0.05)),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: isBest
                                      ? Border.all(
                                          color: theme.colorScheme.primary.withValues(alpha: 0.5),
                                          width: 1.0,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: .min,
                                  children: [
                                    Text(
                                      '${index + 1}. ',
                                      style: TextStyle(
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.bold,
                                        color: textShade(context, 0.5),
                                      ),
                                    ),
                                    Text(
                                      suggestion.san,
                                      style: TextStyle(
                                        fontSize: 13.0,
                                        fontWeight: FontWeight.w700,
                                        color: isBest
                                            ? theme.colorScheme.primary
                                            : theme.textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      suggestion.evalString,
                                      style: TextStyle(
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.w600,
                                        color: scoreColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  // Quick toggle icon
                  GestureDetector(
                    onTap: () => ref.read(liveAssistanceProvider(gameId).notifier).toggleEnabled(),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: Icon(Icons.visibility, size: 16.0, color: textShade(context, 0.5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4.0),

            // 2. Horizontal Evaluation Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3.0),
              child: Container(
                height: 5.0,
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 0.5),
                  borderRadius: BorderRadius.circular(3.0),
                ),
                child: Row(
                  children: [
                    Flexible(
                      flex: (leftFraction * 1000).round(),
                      child: Container(color: leftColor),
                    ),
                    Container(width: 1.0, color: Colors.redAccent.withValues(alpha: 0.8)),
                    Flexible(
                      flex: ((1.0 - leftFraction) * 1000).round(),
                      child: Container(color: rightColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      // In case of any rendering issue, fail gracefully so board layout is completely unaffected
      return const SizedBox.shrink();
    }
  }
}
