import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';
import 'package:lichess_mobile/src/model/game/live_assistance_controller.dart';

class const LiveEvaluationHeader({
  required final GameFullId gameId,
  required final Side orientation,
  final double? width,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final assistance = ref.watch(liveAssistanceProvider(gameId));
      final autoRecapture = ref.watch(autoRecaptureEnabledProvider);

      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

      if (!assistance.enabled) {
        return Container(
          width: width,
          margin: const EdgeInsets.only(bottom: 2.0),
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12.0),
              onTap: () => ref.read(liveAssistanceProvider(gameId).notifier).toggleEnabled(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF262421) : const Color(0xFFEFEFEF),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off,
                      size: 13.0,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      'Show Eval',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final isMyTurn = ref.watch(
        gameControllerProvider(gameId).select((s) => s.value?.game.isMyTurn ?? false),
      );

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
              height: 30.0,
              child: Row(
                children: [
                  Expanded(
                    child: suggestions.isEmpty
                        ? Align(
                            alignment: .centerLeft,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 12.0,
                                  height: 12.0,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  assistance.isComputing
                                      ? (isMyTurn
                                            ? 'Calculating your best moves...'
                                            : 'Analyzing position...')
                                      : 'Waiting for engine...',
                                  style: TextStyle(
                                    fontSize: 12.0,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
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
                              final isZero =
                                  suggestion.evalString == '0.0' || suggestion.evalString == '-0.0';

                              final Color scoreBgColor;
                              final Color scoreTextColor;
                              if (isZero) {
                                scoreBgColor = isDark
                                    ? const Color(0xFF383838)
                                    : const Color(0xFFE0E0E0);
                                scoreTextColor = isDark ? Colors.white70 : Colors.black87;
                              } else if (isWhiteAdvantage) {
                                scoreBgColor = isDark
                                    ? const Color(0xFF1B3820)
                                    : const Color(0xFFE0F2E9);
                                scoreTextColor = isDark
                                    ? const Color(0xFF66BB6A)
                                    : const Color(0xFF2E7D32);
                              } else {
                                scoreBgColor = isDark
                                    ? const Color(0xFF3D1F18)
                                    : const Color(0xFFFFEBE5);
                                scoreTextColor = isDark
                                    ? const Color(0xFFFF7043)
                                    : const Color(0xFFD84315);
                              }

                              final chipBgColor = isDark
                                  ? (isBest ? const Color(0xFF36332E) : const Color(0xFF262421))
                                  : (isBest ? const Color(0xFFEAE8E3) : const Color(0xFFF5F4F0));

                              final chipBorderColor = isBest
                                  ? const Color(0xFF75993B)
                                  : (isDark ? const Color(0xFF484540) : const Color(0xFFD0CFCB));

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6.0),
                                  onTap: isMyTurn
                                      ? () {
                                          try {
                                            ref
                                                .read(gameControllerProvider(gameId).notifier)
                                                .userMove(suggestion.move);
                                          } catch (_) {}
                                        }
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 3.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: chipBgColor,
                                      borderRadius: BorderRadius.circular(6.0),
                                      border: Border.all(
                                        color: chipBorderColor,
                                        width: isBest ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: .min,
                                      children: [
                                        Text(
                                          '${index + 1}. ',
                                          style: TextStyle(
                                            fontSize: 11.0,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? const Color(0xFFA09E99)
                                                : const Color(0xFF6E6C68),
                                          ),
                                        ),
                                        Text(
                                          suggestion.san,
                                          style: TextStyle(
                                            fontSize: 13.0,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF181715),
                                          ),
                                        ),
                                        const SizedBox(width: 5.0),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4.0,
                                            vertical: 1.0,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scoreBgColor,
                                            borderRadius: BorderRadius.circular(3.0),
                                          ),
                                          child: Text(
                                            suggestion.evalString,
                                            style: TextStyle(
                                              fontSize: 11.0,
                                              fontWeight: FontWeight.w700,
                                              color: scoreTextColor,
                                            ),
                                          ),
                                        ),
                                        if (isMyTurn && isBest) ...[
                                          const SizedBox(width: 4.0),
                                          const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 13.0,
                                            color: Color(0xFF75993B),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (!isMyTurn && suggestions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        '(Opponent)',
                        style: TextStyle(
                          fontSize: 10.0,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  // Auto-Recapture toggle button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6.0),
                      onTap: () => ref.read(autoRecaptureEnabledProvider.notifier).toggle(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                        margin: const EdgeInsets.only(left: 4.0),
                        decoration: BoxDecoration(
                          color: autoRecapture
                              ? (isDark ? const Color(0xFF1B3820) : const Color(0xFFE0F2E9))
                              : (isDark ? const Color(0xFF262421) : const Color(0xFFEBEBEB)),
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(
                            color: autoRecapture
                                ? const Color(0xFF75993B)
                                : (isDark ? Colors.white24 : Colors.black12),
                            width: autoRecapture ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.autorenew_rounded,
                              size: 13.0,
                              color: autoRecapture
                                  ? const Color(0xFF75993B)
                                  : (isDark ? Colors.white54 : Colors.black45),
                            ),
                            const SizedBox(width: 2.0),
                            Text(
                              'Auto-Recap',
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.bold,
                                color: autoRecapture
                                    ? (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
                                    : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Quick toggle icon
                  GestureDetector(
                    onTap: () => ref.read(liveAssistanceProvider(gameId).notifier).toggleEnabled(),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: Icon(
                        Icons.visibility,
                        size: 16.0,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
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
