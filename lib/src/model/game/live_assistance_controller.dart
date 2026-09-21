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
  Position? _evaluatedPosition;
  ProviderSubscription<EngineEvaluationState>? _evaluatorSub;
  StreamSubscription<EvalResult>? _streamSub;
  EvaluationContext? _evalContext;
  LiveAssistanceState _currentState = const LiveAssistanceState();

  @override
  LiveAssistanceState build() {
    final enabled = ref.watch(liveAssistanceEnabledProvider);
    _currentState = _currentState.copyWith(enabled: enabled);

    ref.onDispose(() {
      _streamSub?.cancel();
      _evaluatorSub?.close();
    });

    final gameState = ref.watch(gameControllerProvider(gameId)).value;
    if (enabled && gameState != null && gameState.game.playable) {
      final currentPosition = gameState.currentPosition;
      final currentFen = currentPosition.fen;

      if (_lastFen != currentFen) {
        _lastFen = currentFen;
        _evaluatedPosition = currentPosition;

        Future.microtask(() {
          if (ref.mounted) {
            _startEvaluation(
              variant: gameState.game.meta.variant,
              initialPosition: gameState.game.initialPosition,
              currentPosition: currentPosition,
            );
          }
        });
      }
    }

    return _currentState;
  }

  void toggleEnabled() {
    ref.read(liveAssistanceEnabledProvider.notifier).toggle();
  }

  void onPositionChanged({
    required Variant variant,
    required Position initialPosition,
    required Position currentPosition,
  }) {
    _startEvaluation(
      variant: variant,
      initialPosition: initialPosition,
      currentPosition: currentPosition,
    );
  }

  void _startEvaluation({
    required Variant variant,
    required Position initialPosition,
    required Position currentPosition,
  }) {
    if (!_currentState.enabled || !ref.mounted) return;

    try {
      final context = EvaluationContext(
        id: StringId('live_assist_${gameId.value}'),
        variant: variant,
        initialPosition: initialPosition,
      );

      _evaluatedPosition = currentPosition;

      // Keep positionEvaluatorProvider alive via subscription
      if (_evalContext != context || _evaluatorSub == null) {
        _evaluatorSub?.close();
        _evalContext = context;
        _evaluatorSub = ref.listen(positionEvaluatorProvider(context), (prev, next) {
          final eval = next.eval;
          if (eval != null && _evaluatedPosition != null) {
            _handleEvalResult(_evaluatedPosition!, eval);
          }
        });
      }

      final evaluator = ref.read(positionEvaluatorProvider(context).notifier);

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

      _streamSub?.cancel();
      _currentState = _currentState.copyWith(isComputing: true);
      state = _currentState;

      _streamSub = evaluator
          .evaluate(work)
          ?.listen(
            (event) {
              final (_, eval) = event;
              _handleEvalResult(currentPosition, eval);
            },
            onError: (Object _) {
              _currentState = _currentState.copyWith(isComputing: false);
              state = _currentState;
            },
          );
    } catch (_) {
      _currentState = _currentState.copyWith(isComputing: false);
      state = _currentState;
    }
  }

  void _handleEvalResult(Position position, LocalEval eval) {
    if (!ref.mounted) return;
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
              ),
            );
          }
        }
      }

      if (suggestions.isNotEmpty) {
        _currentState = _currentState.copyWith(
          isComputing: false,
          whiteWinningChances: eval.winningChances(Side.white),
          evalString: eval.evalString,
          suggestions: suggestions.toIList(),
        );
        state = _currentState;
      }
    } catch (_) {
      _currentState = _currentState.copyWith(isComputing: false);
      state = _currentState;
    }
  }
}
