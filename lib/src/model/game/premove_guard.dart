import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';

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
        // If our premove is a recapture on that square, it passes section 2
        // and continues to section 3 to ensure the recapturing piece itself doesn't hang.
        if (premove.to != opponentTo) {
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

/// Finds the best legal recapture move in [currentPosition] following [opponentCapture].
///
/// If [anticipatedReply] is provided (e.g. from the engine's principal variation) and is a legal
/// recapture, it is preferred. Otherwise, this evaluates all legal moves landing on
/// [opponentCapture.to], sorting them by piece value ascending (Pawn < Knight/Bishop < Rook < Queen < King)
/// and returns the best non-losing recapture.
Move? findBestRecapture({
  required Position currentPosition,
  required Move opponentCapture,
  required Side mySide,
  required Duration? timeLeft,
  Position? prevPosition,
  Move? anticipatedReply,
}) {
  final targetSquare = opponentCapture.to;

  // 1. If an anticipated engine reply was pre-computed and is a legal recapture, verify and use it
  if (anticipatedReply != null && anticipatedReply.to == targetSquare) {
    if (currentPosition.isLegal(anticipatedReply)) {
      final losing = isPremoveLosing(
        currentPosition: currentPosition,
        prevPosition: prevPosition,
        opponentLastMove: opponentCapture,
        isOpponentCapture: true,
        premove: anticipatedReply,
        mySide: mySide,
        timeLeft: timeLeft,
      );
      if (!losing) {
        return anticipatedReply;
      }
    }
  }

  // 2. Find all legal moves landing on targetSquare
  final candidates = <NormalMove>[];

  for (final entry in currentPosition.legalMoves.entries) {
    final from = entry.key;
    final dests = entry.value;
    if (dests.has(targetSquare)) {
      final move = NormalMove(from: from, to: targetSquare);
      if (isPromotionPawnMove(currentPosition, move)) {
        candidates.add(NormalMove(from: from, to: targetSquare, promotion: Role.queen));
      } else {
        candidates.add(move);
      }
    }
  }

  if (candidates.isEmpty) return null;

  // 3. Sort candidates by piece value ascending:
  // Pawn (1) < Knight (3) == Bishop (3) < Rook (5) < Queen (9) < King (100)
  int recaptureRoleScore(Role role) => switch (role) {
    Role.pawn => 1,
    Role.knight => 3,
    Role.bishop => 3,
    Role.rook => 5,
    Role.queen => 9,
    Role.king => 100,
  };

  candidates.sort((a, b) {
    final roleA = currentPosition.board.roleAt(a.from) ?? Role.queen;
    final roleB = currentPosition.board.roleAt(b.from) ?? Role.queen;
    final scoreDiff = recaptureRoleScore(roleA).compareTo(recaptureRoleScore(roleB));
    if (scoreDiff != 0) return scoreDiff;
    // Tie-breaker for pawns: prefer capturing towards the center files (d and e, files 3 and 4)
    if (roleA == Role.pawn) {
      final distA = (a.from.file - 3.5).abs();
      final distB = (b.from.file - 3.5).abs();
      return distA.compareTo(distB);
    }
    return 0;
  });

  // 4. Return the first non-losing candidate
  for (final candidate in candidates) {
    final losing = isPremoveLosing(
      currentPosition: currentPosition,
      prevPosition: prevPosition,
      opponentLastMove: opponentCapture,
      isOpponentCapture: true,
      premove: candidate,
      mySide: mySide,
      timeLeft: timeLeft,
    );
    if (!losing) {
      return candidate;
    }
  }

  // 5. If under 5 seconds, play the first legal candidate anyway to avoid flagging
  if (timeLeft != null && timeLeft < const Duration(seconds: 5)) {
    return candidates.firstOrNull;
  }

  return null;
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
