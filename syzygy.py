"""Syzygy tablebase integration for Bytefish."""

from __future__ import annotations

import os
from pathlib import Path
from typing import TYPE_CHECKING

import chess
import chess.syzygy

if TYPE_CHECKING:
    from board import Board


class SyzygyTablebase:
    """Read WDL results from a directory containing Syzygy tablebases."""

    def __init__(self, path: str | Path | None = None) -> None:
        self._tablebase: chess.syzygy.Tablebase | None = None
        self.path: Path | None = None

        if path:
            self.open(path)

    def open(self, path: str | Path) -> None:
        tablebase_path = Path(path).expanduser()
        if not tablebase_path.is_dir():
            raise FileNotFoundError(
                f"Syzygy tablebase directory does not exist: {tablebase_path}"
            )

        if self._tablebase is not None:
            self._tablebase.close()

        self._tablebase = chess.syzygy.open_tablebase(str(tablebase_path))
        self.path = tablebase_path

    def close(self) -> None:
        if self._tablebase is not None:
            self._tablebase.close()
            self._tablebase = None

    def probe_wdl(self, board: Board) -> int | None:
        """Return WDL from the side-to-move perspective, or None if unavailable."""
        if self._tablebase is None or self._piece_count(board) > 5:
            return None

        chess_board = chess.Board(board.to_fen())
        try:
            return int(self._tablebase.probe_wdl(chess_board))
        except (KeyError, RuntimeError, ValueError):
            return None

    def probe_dtz(self, board: Board) -> int | None:
        """Return Syzygy DTZ from the side-to-move perspective, if available."""
        if self._tablebase is None or self._piece_count(board) > 5:
            return None

        chess_board = chess.Board(board.to_fen())
        try:
            return int(self._tablebase.probe_dtz(chess_board))
        except (KeyError, RuntimeError, ValueError):
            return None

    @staticmethod
    def _piece_count(board: Board) -> int:
        return sum(
            piece != ""
            for row in board.board
            for piece in row
        )

    @staticmethod
    def default_path() -> Path | None:
        candidates = []
        configured = os.environ.get("BYTEFISH_SYZYGY_PATH")
        if configured:
            candidates.append(Path(configured).expanduser())

        candidates.extend(
            (
                Path.cwd() / "syzygy",
                Path(__file__).resolve().parent.parent / "syzygy",
            )
        )

        return next((path for path in candidates if path.is_dir()), None)
