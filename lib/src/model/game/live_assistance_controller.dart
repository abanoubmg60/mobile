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
  StreamSubscription<EvalResult>? _evalSubscription;
  EvaluationContext? _evalContext;
  LiveAssistanceState _currentState = const LiveAssistanceState();

  @override
  LiveAssistanceState build() {
    final enabled = ref.watch(liveAssistanceEnabledProvider);
    _currentState = _currentState.copyWith(enabled: enabled);

    ref.onDispose(() {
      _evalSubscription?.cancel();
    });

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
    if (!_currentState.enabled) return;

    final currentFen = currentPosition.fen;
    if (_lastFen == currentFen) return;
    _lastFen = currentFen;

    try {
      _evalContext ??= EvaluationContext(
        id: StringId('live_assist_${gameId.value}'),
        variant: variant,
        initialPosition: initialPosition,
      );

      final evaluator = ref.read(positionEvaluatorProvider(_evalContext!).notifier);

      final work = EvalWork(
        id: StringId('live_assist_${gameId.value}'),
        variant: variant,
        threads: 1,
        searchTime: const Duration(milliseconds: 300),
        multiPv: 3,
        threatMode: false,
        initialPosition: currentPosition,
        steps: const IListConst([]),
      );

      _evalSubscription?.cancel();
      _currentState = _currentState.copyWith(isComputing: true);
      state = _currentState;

      _evalSubscription = evaluator
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

      _currentState = _currentState.copyWith(
        isComputing: false,
        whiteWinningChances: eval.winningChances(Side.white),
        evalString: eval.evalString,
        suggestions: suggestions.toIList(),
      );
      state = _currentState;
    } catch (_) {
      _currentState = _currentState.copyWith(isComputing: false);
      state = _currentState;
    }
  }
}
