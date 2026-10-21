"""Tests for the ledger."""
import pytest

from ledger.core import Ledger


def test_entry_0():
    ledger = Ledger()
    ledger.add(0, "item 0")
    assert ledger.total() == 0

