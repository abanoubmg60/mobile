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
  required final Move move,
});

@immutable
class const LiveAssistanceState({
  final bool enabled = true,
  final bool isComputing = false,
  final double? whiteWinningChances = 0.0,
  final String? evalString,
  final IList<LiveMoveSuggestion> suggestions = const IListConst([]),
}) {
  LiveAssistanceState copyWith({
    bool? enabled,
    bool? isComputing,
    double? whiteWinningChances,
    String? evalString,
    IList<LiveMoveSuggestion>? suggestions,
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
final liveAssistanceEnabledProvider = NotifierProvider<LiveAssistanceEnabledNotifier, bool>(
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
  try {
    final (_, san) = position.makeSan(move);
    if (san.isEmpty) return san;
    final first = san[0];
    switch (first) {
      case 'N':
        return '♞${san.substring(1)}';
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
  } catch (_) {
    return move.uci;
  }
}

final liveAssistanceProvider = NotifierProvider.autoDispose
    .family<LiveAssistanceNotifier, LiveAssistanceState, GameFullId>(
      LiveAssistanceNotifier.new,
      name: 'LiveAssistanceProvider',
    );

class LiveAssistanceNotifier(final GameFullId gameId) extends Notifier<LiveAssistanceState> {
  String? _lastFen;
  ProviderSubscription<EngineEvaluationState>? _evaluatorKeepAlive;
  StreamSubscription<EvalResult>? _streamSub;
  EvaluationContext? _evalContext;

  @override
  LiveAssistanceState build() {
    final enabled = ref.watch(liveAssistanceEnabledProvider);

    ref.onDispose(() {
      _streamSub?.cancel();
      _streamSub = null;
      _evaluatorKeepAlive?.close();
      _evaluatorKeepAlive = null;
      if (_evalContext != null) {
        try {
          ref.read(positionEvaluatorProvider(_evalContext!).notifier).stop();
        } catch (_) {}
      }
    });

    if (!enabled) {
      return const LiveAssistanceState(enabled: false);
    }

    final initialGameState = ref.read(gameControllerProvider(gameId)).value;
    if (initialGameState != null && initialGameState.game.playable) {
      Future.microtask(() {
        if (ref.mounted) {
          _onPositionChanged(
            variant: initialGameState.game.meta.variant,
            initialPosition: initialGameState.game.initialPosition,
            currentPosition: initialGameState.currentPosition,
          );
        }
      });
    }

    // Listen to game position changes without rebuilding this notifier
    ref.listen(
      gameControllerProvider(gameId).select((s) {
        final st = s.value;
        if (st == null) return null;
        return (
          playable: st.game.playable,
          variant: st.game.meta.variant,
          initialPosition: st.game.initialPosition,
          currentPosition: st.currentPosition,
        );
      }),
      (prev, next) {
        if (next != null && next.playable) {
          _onPositionChanged(
            variant: next.variant,
            initialPosition: next.initialPosition,
            currentPosition: next.currentPosition,
          );
        }
      },
    );

    return const LiveAssistanceState(enabled: true, isComputing: true);
  }

  void toggleEnabled() {
    ref.read(liveAssistanceEnabledProvider.notifier).toggle();
  }

  void _onPositionChanged({
    required Variant variant,
    required Position initialPosition,
    required Position currentPosition,
  }) {
    if (!state.enabled || !ref.mounted) return;

    final currentFen = currentPosition.fen;
    if (_lastFen == currentFen) return;
    _lastFen = currentFen;

    // Cancel active search and subscription
    _streamSub?.cancel();
    _streamSub = null;

    final context = EvaluationContext(
      id: StringId('live_assist_${gameId.value}'),
      variant: variant,
      initialPosition: initialPosition,
    );

    // Keep positionEvaluatorProvider alive so it doesn't auto-dispose
    if (_evalContext != context || _evaluatorKeepAlive == null) {
      _evaluatorKeepAlive?.close();
      _evalContext = context;
      _evaluatorKeepAlive = ref.listen(positionEvaluatorProvider(context), (_, _) {});
    }

    final evaluator = ref.read(positionEvaluatorProvider(context).notifier);
    evaluator.stop();

    state = state.copyWith(isComputing: true, suggestions: const IListConst([]));

    final work = EvalWork(
      id: StringId('live_assist_${gameId.value}'),
      variant: variant,
      threads: 1,
      searchTime: const Duration(seconds: 3),
      multiPv: 3,
      threatMode: false,
      initialPosition: currentPosition,
      steps: const IListConst([]),
    );

    try {
      _streamSub = evaluator
          .evaluate(work)
          ?.listen(
            (event) {
              final (_, eval) = event;
              _handleEvalResult(currentPosition, eval);
            },
            onError: (Object _) {
              if (ref.mounted && _lastFen == currentFen) {
                state = state.copyWith(isComputing: false);
              }
            },
          );
    } catch (_) {
      if (ref.mounted && _lastFen == currentFen) {
        state = state.copyWith(isComputing: false);
      }
    }
  }

  void _handleEvalResult(Position position, LocalEval eval) {
    if (!ref.mounted) return;
    if (_lastFen != position.fen) return;

    try {
      final suggestions = <LiveMoveSuggestion>[];
      for (final pv in eval.pvs.take(3)) {
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
                move: move,
              ),
            );
          }
        }
      }

      if (suggestions.isNotEmpty && _lastFen == position.fen) {
        state = state.copyWith(
          isComputing: false,
          whiteWinningChances: eval.winningChances(Side.white),
          evalString: eval.evalString,
          suggestions: suggestions.toIList(),
        );
      }
    } catch (_) {
      if (ref.mounted && _lastFen == position.fen) {
        state = state.copyWith(isComputing: false);
      }
    }
  }
}
