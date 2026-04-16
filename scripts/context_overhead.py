#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
PCM_ROOT = (ROOT / "../product-context-manager").resolve()
QUEUE_PATH = ROOT / "docs/queue.md"
PROJECT_TEMPLATE_PATH = PCM_ROOT / "project-template.md"


try:
    import tiktoken  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    tiktoken = None


LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+\.md)\)")


@dataclass(frozen=True)
class DocStats:
    path: Path
    bytes: int
    chars: int
    lines: int
    words: int
    tokens_o200k: int | None

    @classmethod
    def from_path(cls, path: Path) -> "DocStats":
        text = path.read_text()
        return cls(
            path=path.resolve(),
            bytes=path.stat().st_size,
            chars=len(text),
            lines=text.count("\n") + (0 if text.endswith("\n") else 1),
            words=len(text.split()),
            tokens_o200k=token_count(text),
        )

    def as_dict(self) -> dict[str, object]:
        return {
            "path": str(self.path),
            "bytes": self.bytes,
            "chars": self.chars,
            "lines": self.lines,
            "words": self.words,
            "tokens_o200k": self.tokens_o200k,
        }


def token_count(text: str) -> int | None:
    if tiktoken is None:
        return None
    encoding = tiktoken.get_encoding("o200k_base")
    return len(encoding.encode(text))


def sum_stats(paths: Iterable[Path]) -> dict[str, object]:
    docs = [DocStats.from_path(path) for path in unique_existing(paths)]
    return {
        "count": len(docs),
        "bytes": sum(doc.bytes for doc in docs),
        "chars": sum(doc.chars for doc in docs),
        "lines": sum(doc.lines for doc in docs),
        "words": sum(doc.words for doc in docs),
        "tokens_o200k": maybe_sum(doc.tokens_o200k for doc in docs),
        "docs": [doc.as_dict() for doc in docs],
    }


def maybe_sum(values: Iterable[int | None]) -> int | None:
    values = list(values)
    if any(value is None for value in values):
        return None
    return sum(value for value in values if value is not None)


def unique_existing(paths: Iterable[Path]) -> list[Path]:
    seen: set[Path] = set()
    ordered: list[Path] = []
    for path in paths:
        resolved = path.resolve()
        if not resolved.exists() or resolved in seen:
            continue
        seen.add(resolved)
        ordered.append(resolved)
    return ordered


def resolve_base_docs() -> dict[str, list[Path]]:
    default = [
        ROOT / "AGENTS.md",
        PCM_ROOT / "principles.md",
        PCM_ROOT / "rules.md",
        ROOT / "docs/rules.md",
        PCM_ROOT / "workflow.md",
        ROOT / "docs/product.md",
    ]
    return {
        "default_load": default,
        "routing_extra": [QUEUE_PATH],
        "new_project_extra": [PROJECT_TEMPLATE_PATH],
        "task_extra": [PCM_ROOT / "tasks/README.md"],
    }


def markdown_links(path: Path) -> list[Path]:
    text = path.read_text()
    paths: list[Path] = []
    for raw_target in LINK_RE.findall(text):
        target = raw_target.split("#", 1)[0]
        if not target:
            continue
        if target.startswith("/"):
            resolved = Path(target)
        else:
            resolved = (path.parent / target).resolve()
        if resolved.suffix == ".md" and resolved.exists():
            paths.append(resolved)
    return unique_existing(paths)


def queue_linked_docs() -> list[Path]:
    return markdown_links(QUEUE_PATH)


def active_queue_docs() -> list[Path]:
    return [path for path in queue_linked_docs() if "/docs/active/" in str(path)]


def backlog_queue_docs() -> list[Path]:
    return [path for path in queue_linked_docs() if "/docs/backlog/" in str(path)]


def expanded_project_bundle(project_doc: Path) -> list[Path]:
    return unique_existing([project_doc, *markdown_links(project_doc)])


def report() -> dict[str, object]:
    base = resolve_base_docs()
    active_docs = active_queue_docs()
    backlog_docs = backlog_queue_docs()

    scenarios: dict[str, dict[str, object]] = {
        "default_load": sum_stats(base["default_load"]),
        "default_plus_queue": sum_stats([*base["default_load"], *base["routing_extra"]]),
        "default_plus_task_readme": sum_stats([*base["default_load"], *base["task_extra"]]),
        "new_project_creation": sum_stats([*base["default_load"], *base["routing_extra"], *base["new_project_extra"]]),
        "queue_linked_all": sum_stats([*base["default_load"], *base["routing_extra"], *queue_linked_docs()]),
        "queue_linked_active": sum_stats([*base["default_load"], *base["routing_extra"], *active_docs]),
        "queue_linked_backlog": sum_stats([*base["default_load"], *base["routing_extra"], *backlog_docs]),
    }

    per_project: dict[str, dict[str, object]] = {}
    for project_doc in active_docs + backlog_docs:
        key = str(project_doc.relative_to(ROOT))
        per_project[key] = {
            "entry_only": sum_stats([*base["default_load"], *base["routing_extra"], project_doc]),
            "expanded_links": sum_stats([*base["default_load"], *base["routing_extra"], *expanded_project_bundle(project_doc)]),
        }

    return {
        "tokenizer": "o200k_base" if tiktoken is not None else None,
        "paths": {
            "root": str(ROOT),
            "product_context_manager_root": str(PCM_ROOT),
        },
        "base_docs": {
            key: [str(path.resolve()) for path in value]
            for key, value in base.items()
        },
        "queue_linked_docs": [str(path) for path in queue_linked_docs()],
        "scenarios": scenarios,
        "per_project": per_project,
    }


def print_human(report_data: dict[str, object]) -> None:
    tokenizer = report_data["tokenizer"]
    print("Context Overhead Report")
    print(f"Root: {report_data['paths']['root']}")
    print(f"Tokenizer: {tokenizer or 'not available'}")
    print()

    print("Scenario totals")
    for name, scenario in report_data["scenarios"].items():
        tokens = scenario["tokens_o200k"]
        token_part = f", tokens_o200k={tokens}" if tokens is not None else ""
        print(
            f"- {name}: files={scenario['count']}, bytes={scenario['bytes']}, "
            f"chars={scenario['chars']}, lines={scenario['lines']}, words={scenario['words']}{token_part}"
        )
    print()

    print("Per-project totals")
    for project, payload in report_data["per_project"].items():
        entry = payload["entry_only"]
        expanded = payload["expanded_links"]
        entry_tokens = entry["tokens_o200k"]
        expanded_tokens = expanded["tokens_o200k"]
        entry_token_part = f", tokens_o200k={entry_tokens}" if entry_tokens is not None else ""
        expanded_token_part = f", tokens_o200k={expanded_tokens}" if expanded_tokens is not None else ""
        print(
            f"- {project}: "
            f"entry_only(files={entry['count']}, bytes={entry['bytes']}, words={entry['words']}{entry_token_part}) | "
            f"expanded_links(files={expanded['count']}, bytes={expanded['bytes']}, words={expanded['words']}{expanded_token_part})"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Report Product Context Manager prompt overhead.")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of human-readable text.")
    args = parser.parse_args()

    report_data = report()
    if args.json:
        print(json.dumps(report_data, indent=2))
    else:
        print_human(report_data)


if __name__ == "__main__":
    main()
