"""Write a reference stream for every case."""
import sys

CASES = ["basic", "glow-i16", "glow-i32", "glow-i64"]


def generate(case: str) -> list[dict]:
