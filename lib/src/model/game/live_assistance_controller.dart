import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_context.dart';
import 'package:lichess_mobile/src/model/engine/position_evaluator.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';

@immutable
class const LiveMoveSuggestion({
  required final String san,
  required final String evalString,
  required final double winningChances,
});

@immutable
class const LiveAssistanceState({
  final bool enabled = true,
  final bool isComputing = false,
  final double? whiteWinningChances = 0.0,
  final String? evalString,
  final List<LiveMoveSuggestion> suggestions = const [],
}) {
  LiveAssistanceState copyWith({
    bool? enabled,
    bool? isComputing,
    double? whiteWinningChances,
    String? evalString,
    List<LiveMoveSuggestion>? suggestions,
  }) {
    return LiveAssistanceState(
      enabled: enabled ?? this.enabled,
      isComputing: isComputing ?? this.isComputing,
      whiteWinningChances: whiteWinningChances ?? this.whiteWinningChances,
      evalString: evalString ?? this.evalString,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}

/// Global toggle to enable/disable live assistance.
final liveAssistanceEnabledProvider =
    NotifierProvider<LiveAssistanceEnabledNotifier, bool>(
      LiveAssistanceEnabledNotifier.new,
      name: 'LiveAssistanceEnabledProvider',
    );

class LiveAssistanceEnabledNotifier() extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

/// Formats a SAN string with clean unicode piece symbols.
String formatSanWithPieceEmoji(Position position, Move move) {
  final (_, san) = position.makeSan(move);
  if (san.isEmpty) return san;
  final first = san[0];
  switch (first) {
    case 'N':
      return '♘${san.substring(1)}';
    case 'B':
      return '♗${san.substring(1)}';
    case 'R':
      return '♖${san.substring(1)}';
    case 'Q':
      return '♕${san.substring(1)}';
    case 'K':
      return '♔${san.substring(1)}';
    case 'O':
      return san;
    default:
      return '♟$san';
  }
}

final liveAssistanceProvider = NotifierProvider.autoDispose
    .family<LiveAssistanceNotifier, LiveAssistanceState, GameFullId>(
      LiveAssistanceNotifier.new,
      name: 'LiveAssistanceProvider',
    );

class LiveAssistanceNotifier(final GameFullId gameId) extends Notifier<LiveAssistanceState> {
  String? _lastFen;
  ProviderSubscription<EngineEvaluationState>? _evalSubscription;

  @override
  LiveAssistanceState build() {
    final enabled = ref.watch(liveAssistanceEnabledProvider);

    // Watch game state to trigger evaluations on position changes
    final gameState = ref.watch(gameControllerProvider(gameId)).value;

    if (!enabled || gameState == null || !gameState.game.playable) {
      return LiveAssistanceState(enabled: enabled);
    }

    final currentPosition = gameState.currentPosition;
    final currentFen = currentPosition.fen;

    if (_lastFen != currentFen) {
      _lastFen = currentFen;
      // Schedule evaluation on next microtask to avoid side-effects during build
      Future.microtask(() => _evaluatePosition(gameState.game.meta.variant, currentPosition));
    }

    return state;
  }

  void toggleEnabled() {
    ref.read(liveAssistanceEnabledProvider.notifier).toggle();
  }

  void _evaluatePosition(Variant variant, Position position) {
    if (!state.enabled) return;

    final evalContext = EvaluationContext(
      id: StringId(gameId.value),
      variant: variant,
      initialPosition: position,
    );

    // Cancel existing evaluator subscription
    _evalSubscription?.close();

    // Listen to engine output
    _evalSubscription = ref.listen(
      positionEvaluatorProvider(evalContext),
      (EngineEvaluationState? prev, EngineEvaluationState next) {
        final ClientEval? eval = next.eval;
        if (eval == null) return;

        final pvs = eval.pvs;
        final suggestions = <LiveMoveSuggestion>[];

        for (final pv in pvs.take(3)) {
          final uci = pv.moves.firstOrNull;
          if (uci != null) {
            final move = Move.parse(uci);
            if (move != null) {
              final san = formatSanWithPieceEmoji(position, move);
              suggestions.add(
                LiveMoveSuggestion(
                  san: san,
                  evalString: pv.evalString,
                  winningChances: pv.winningChances(Side.white),
                ),
              );
            }
          }
        }

        state = state.copyWith(
          isComputing: next.isComputing,
          whiteWinningChances: eval.winningChances(Side.white),
          evalString: eval.evalString,
          suggestions: suggestions,
        );
      },
    );

    final evaluator = ref.read(positionEvaluatorProvider(evalContext).notifier);
    evaluator.evaluate(
      EvalWork(
        id: StringId(gameId.value),
        variant: variant,
        threads: 1,
        searchTime: const Duration(milliseconds: 300),
        multiPv: 3,
        threatMode: false,
        initialPosition: position,
        steps: const IListConst([]),
      ),
    );
  }
}
