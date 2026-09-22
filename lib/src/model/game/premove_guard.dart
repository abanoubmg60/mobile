import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

const IMap<Role, int> pieceRoleValues = IMapConst({
  Role.pawn: 1,
  Role.knight: 3,
  Role.bishop: 3,
  Role.rook: 5,
  Role.queen: 9,
  Role.king: 0,
});

/// Evaluates whether a queued [premove] will lead to a losing position.
///
/// Returns `true` if the premove is detected as a blunder (e.g. failing to
/// recapture a captured piece, hanging a piece for free, or walking into mate),
/// in which case the premove should be prevented.
///
/// [timeLeft] is the player's remaining clock time. If time is strictly less
/// than 5 seconds, this guard unconditionally returns `false` so the player
/// does not lose on time.
bool isPremoveLosing({
  required Position currentPosition,
  required Position? prevPosition,
  required Move? opponentLastMove,
  required bool isOpponentCapture,
  required Move premove,
  required Side mySide,
  required Duration? timeLeft,
}) {
  // 1. Clock threshold bypass: allow all premoves if under 5 seconds remaining
  if (timeLeft != null && timeLeft < const Duration(seconds: 5)) {
    return false;
  }

  // 2. Opponent captured our piece scenario:
  // If the opponent captured our piece and a recapture is available on that square,
  // but the premove fails to recapture (and doesn't deliver mate or counter-capture equal/higher material),
  // then the premove blunders the piece for free and leads to a losing state.
  if (opponentLastMove != null && isOpponentCapture && prevPosition != null) {
    final opponentTo = opponentLastMove.to;
    final capturedPiece = prevPosition.board.pieceAt(opponentTo);

    if (capturedPiece != null && capturedPiece.color == mySide) {
      final capturedValue = pieceRoleValues[capturedPiece.role] ?? 1;

      // Are there legal recapture moves on that square?
      final canRecapture = currentPosition.legalMoves.values.any((dests) => dests.has(opponentTo));
      if (canRecapture) {
        // If our premove is a recapture on that square, it's the intended reply!
        if (premove.to == opponentTo) {
          return false;
        }

        // Check if premove delivers checkmate
        try {
          final posAfterPremove = currentPosition.playUnchecked(premove);
          if (posAfterPremove.isCheckmate) {
            return false;
          }
        } catch (_) {}

        // Check if premove counter-captures equal or higher value piece elsewhere
        if (premove is NormalMove) {
          final targetPiece = currentPosition.board.pieceAt(premove.to);
          if (targetPiece != null && targetPiece.color == mySide.opposite) {
            final targetValue = pieceRoleValues[targetPiece.role] ?? 0;
            if (targetValue >= capturedValue) {
              return false;
            }
          }
        }

        // Premove plays an unrelated move without recapturing the lost piece -> BLUNDER!
        return true;
      }
    }
  }

  // 3. Hanging piece blunder check:
  // Check if premove moves a valuable piece into an undefended attack or lower-value attacker
  if (premove is NormalMove) {
    final movingPiece = currentPosition.board.pieceAt(premove.from);
    if (movingPiece != null && movingPiece.color == mySide && movingPiece.role != Role.pawn) {
      try {
        final posAfter = currentPosition.playUnchecked(premove);
        if (posAfter.isCheckmate) {
          return true; // Walks into checkmate
        }

        final opponentSide = mySide.opposite;
        final attackers = posAfter.board.attacksTo(premove.to, opponentSide);
        final defenders = posAfter.board.attacksTo(premove.to, mySide);

        if (attackers.isNotEmpty) {
          // If completely undefended and attacker can capture our piece:
          if (defenders.isEmpty) {
            return true;
          }

          final myValue = pieceRoleValues[movingPiece.role] ?? 0;
          // Check if any attacker has strictly lower value than our piece (e.g. Queen attacked by Pawn)
          for (final attackerSquare in attackers.squares) {
            final attackerPiece = posAfter.board.pieceAt(attackerSquare);
            if (attackerPiece != null) {
              final attackerValue = pieceRoleValues[attackerPiece.role] ?? 0;
              if (attackerValue < myValue) {
                return true; // Trades Queen/Rook for a lesser piece
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  return false;
}

/// Checks whether [candidateMove] recaptures the piece on [opponentLastMove]'s destination.
bool isRecaptureMove({
  required Move candidateMove,
  required Move? opponentLastMove,
  required bool isOpponentCapture,
}) {
  if (opponentLastMove == null || !isOpponentCapture) return false;
  return candidateMove.to == opponentLastMove.to;
}
