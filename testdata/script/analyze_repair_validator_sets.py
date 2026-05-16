#!/usr/bin/env python3
"""Extract repair validator-set activation data from BSC logs."""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[0]
DEFAULT_LOG_ROOT = SCRIPT_DIR / ".local"
DEFAULT_VALIDATORS_FILE = REPO_ROOT / "code/repair-code/params/validators.go"
DEFAULT_EVENTS_OUTPUT = SCRIPT_DIR / "repair_validator_set_changes.csv"
DEFAULT_SERIES_OUTPUT = SCRIPT_DIR / "repair_validator_set_series.csv"
DEFAULT_ASSIGNMENT_OUTPUT = SCRIPT_DIR / "repair_validator_assignments.csv"

SET_Y = {
    "V": 0,
    "V_A": 1,
    "V_B": 2,
    "V_A+V_B": 3,
    "unknown": -1,
}

ADDR_RE = re.compile(r"0x[0-9a-fA-F]+")
CONST_RE = re.compile(r"\b(?P<name>expAddr\w+)\s*=\s*\"(?P<addr>0x[0-9a-fA-F]+)\"")
VAR_BLOCK_RE = re.compile(
    r"var\s+(?P<name>AllValidators|ValidatorsAddA|ValidatorsAddB)\s*=\s*map\[string\]string\s*\{"
    r"(?P<body>.*?)\n\}",
    re.S,
)
MAP_ENTRY_RE = re.compile(r'"(?P<addr>0x[0-9a-fA-F]+)":\s*"[^"]+",\s*//\s*(?P<label>\S+)')
NODE_COMMENT_RE = re.compile(r'"(?P<addr>0x[0-9a-fA-F]+)":\s*"[^"]+",\s*//\s*(?P<node>\d+)\b')
NODE_DIR_RE = re.compile(r"node(?P<node>\d+)$")
VALIDATOR_CHANGE_RE = re.compile(
    r'msg="\[ValidatorElection\] Validator set changes".*?\bblock=(?P<block>\d+)'
    r".*?\bcandidates=(?P<candidates>\d+)"
    r'.*?\beValidators="\[(?P<validators>[^\]]*)\]"'
    r'(?:.*?\beVotingPowers="\[(?P<powers>[^\]]*)\]")?'
)


@dataclass(frozen=True)
class ValidatorGroups:
    all_validators: set[str]
    baseline: set[str]
    candidate_a: set[str]
    candidate_b: set[str]
    addr_to_node: dict[str, str]
    addr_to_label: dict[str, str]


@dataclass(frozen=True)
class ValidatorSetChange:
    block: int
    node: str
    log_path: Path
    candidates: int
    validators: tuple[str, ...]
    powers: tuple[int, ...]
    set_label: str
    base_count: int
    add_a_count: int
    add_b_count: int
    unknown_count: int


def normalize(addr: str) -> str:
    return addr.lower()


def parse_validators(validators_file: Path) -> ValidatorGroups:
    text = validators_file.read_text(encoding="utf-8", errors="replace")
    addr_to_node: dict[str, str] = {}
    for match in NODE_COMMENT_RE.finditer(text):
        # Keep the first numeric comment block; later comments may be short labels.
        addr_to_node.setdefault(normalize(match.group("addr")), match.group("node"))

    addr_to_label: dict[str, str] = {}
    named_sets: dict[str, set[str]] = {}
    for match in VAR_BLOCK_RE.finditer(text):
        name = match.group("name")
        body = match.group("body")
        addresses: set[str] = set()
        for entry in MAP_ENTRY_RE.finditer(body):
            addr = normalize(entry.group("addr"))
            addresses.add(addr)
            if name == "AllValidators":
                addr_to_label[addr] = entry.group("label")
        named_sets[name] = addresses

    all_validators = named_sets.get("AllValidators", set())
    candidate_a = named_sets.get("ValidatorsAddA", set())
    candidate_b = named_sets.get("ValidatorsAddB", set())
    baseline = all_validators - candidate_a - candidate_b
    if not all_validators or not baseline:
        raise ValueError(f"failed to parse validator groups from {validators_file}")

    return ValidatorGroups(
        all_validators=all_validators,
        baseline=baseline,
        candidate_a=candidate_a,
        candidate_b=candidate_b,
        addr_to_node=addr_to_node,
        addr_to_label=addr_to_label,
    )


def discover_logs(log_root: Path, log_glob: str) -> list[Path]:
    return sorted(path for path in log_root.glob(f"node*/{log_glob}") if path.is_file())


def classify_validator_set(validators: set[str], groups: ValidatorGroups) -> str:
    if validators == groups.baseline:
        return "V"
    if validators == groups.baseline | groups.candidate_a:
        return "V_A"
    if validators == groups.baseline | groups.candidate_b:
        return "V_B"
    if validators == groups.all_validators:
        return "V_A+V_B"
    return "unknown"


def parse_powers(raw: str | None) -> tuple[int, ...]:
    if raw is None or not raw.strip():
        return ()
    return tuple(int(value) for value in raw.split())


def parse_change_line(line: str, log_path: Path, groups: ValidatorGroups) -> ValidatorSetChange | None:
    match = VALIDATOR_CHANGE_RE.search(line)
    if not match:
        return None
    node_match = NODE_DIR_RE.fullmatch(log_path.parent.name)
    if not node_match:
        return None

    validators = tuple(normalize(addr) for addr in ADDR_RE.findall(match.group("validators")))
    validator_set = set(validators)
    return ValidatorSetChange(
        block=int(match.group("block")),
        node=node_match.group("node"),
        log_path=log_path,
        candidates=int(match.group("candidates")),
        validators=validators,
        powers=parse_powers(match.group("powers")),
        set_label=classify_validator_set(validator_set, groups),
        base_count=len(validator_set & groups.baseline),
        add_a_count=len(validator_set & groups.candidate_a),
        add_b_count=len(validator_set & groups.candidate_b),
        unknown_count=len(validator_set - groups.all_validators),
    )


def parse_changes(log_paths: list[Path], groups: ValidatorGroups, end: int | None) -> list[ValidatorSetChange]:
    changes: list[ValidatorSetChange] = []
    for log_path in log_paths:
        with log_path.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                change = parse_change_line(line, log_path, groups)
                if change is None:
                    continue
                if end is not None and change.block > end:
                    continue
                changes.append(change)
    changes.sort(key=lambda change: (change.block, change.node, str(change.log_path)))
    return changes


def write_assignments(groups: ValidatorGroups, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "address",
                "node",
                "label",
                "role",
                "in_V",
                "in_V_A",
                "in_V_B",
                "in_V_A_plus_V_B",
            ],
        )
        writer.writeheader()
        for addr in sorted(groups.all_validators):
            if addr in groups.candidate_a:
                role = "candidate_V_A"
            elif addr in groups.candidate_b:
                role = "candidate_V_B"
            else:
                role = "honest_validator"
            writer.writerow(
                {
                    "address": addr,
                    "node": groups.addr_to_node.get(addr, ""),
                    "label": groups.addr_to_label.get(addr, ""),
                    "role": role,
                    "in_V": int(addr in groups.baseline),
                    "in_V_A": int(addr in groups.baseline or addr in groups.candidate_a),
                    "in_V_B": int(addr in groups.baseline or addr in groups.candidate_b),
                    "in_V_A_plus_V_B": 1,
                }
            )


def write_events(changes: list[ValidatorSetChange], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "slot",
                "node",
                "log_path",
                "activated_validator_set",
                "activated_validator_set_y",
                "candidates",
                "validator_count",
                "honest_count",
                "candidate_a_count",
                "candidate_b_count",
                "unknown_count",
                "e_validators",
                "e_voting_powers",
            ],
        )
        writer.writeheader()
        for change in changes:
            writer.writerow(
                {
                    "slot": change.block,
                    "node": change.node,
                    "log_path": str(change.log_path),
                    "activated_validator_set": change.set_label,
                    "activated_validator_set_y": SET_Y.get(change.set_label, -1),
                    "candidates": change.candidates,
                    "validator_count": len(change.validators),
                    "honest_count": change.base_count,
                    "candidate_a_count": change.add_a_count,
                    "candidate_b_count": change.add_b_count,
                    "unknown_count": change.unknown_count,
                    "e_validators": " ".join(change.validators),
                    "e_voting_powers": " ".join(str(power) for power in change.powers),
                }
            )


def build_series(
    changes: list[ValidatorSetChange],
    start: int,
    end: int,
    default_set: str = "V",
) -> list[dict[str, int | str]]:
    by_node: dict[str, list[ValidatorSetChange]] = {}
    for change in changes:
        by_node.setdefault(change.node, []).append(change)

    rows: list[dict[str, int | str]] = []
    node_states = {node: default_set for node in by_node}
    node_indexes = {node: 0 for node in by_node}
    for slot in range(start, end + 1):
        for node, node_changes in by_node.items():
            idx = node_indexes[node]
            while idx < len(node_changes) and node_changes[idx].block <= slot:
                node_states[node] = node_changes[idx].set_label
                idx += 1
            node_indexes[node] = idx

        counts = Counter(node_states.values())
        if counts:
            activated_set, activated_count = counts.most_common(1)[0]
        else:
            activated_set, activated_count = default_set, 0
        rows.append(
            {
                "slot": slot,
                "activated_validator_set": activated_set,
                "activated_validator_set_y": SET_Y.get(activated_set, -1),
                "node_count": len(node_states),
                "activated_node_count": activated_count,
                "V_count": counts.get("V", 0),
                "V_A_count": counts.get("V_A", 0),
                "V_B_count": counts.get("V_B", 0),
                "V_A_plus_V_B_count": counts.get("V_A+V_B", 0),
                "unknown_count": counts.get("unknown", 0),
            }
        )
    return rows


def write_series(rows: list[dict[str, int | str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "slot",
                "activated_validator_set",
                "activated_validator_set_y",
                "node_count",
                "activated_node_count",
                "V_count",
                "V_A_count",
                "V_B_count",
                "V_A_plus_V_B_count",
                "unknown_count",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze repair validator-set activation logs.")
    parser.add_argument("--log-root", type=Path, default=DEFAULT_LOG_ROOT)
    parser.add_argument("--log-glob", default="bsc.log*")
    parser.add_argument("--validators", type=Path, default=DEFAULT_VALIDATORS_FILE)
    parser.add_argument("--start", type=int, default=300)
    parser.add_argument("--end", type=int, default=620)
    parser.add_argument("--events-output", type=Path, default=DEFAULT_EVENTS_OUTPUT)
    parser.add_argument("--series-output", type=Path, default=DEFAULT_SERIES_OUTPUT)
    parser.add_argument("--assignment-output", type=Path, default=DEFAULT_ASSIGNMENT_OUTPUT)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    groups = parse_validators(args.validators)
    log_paths = discover_logs(args.log_root, args.log_glob)
    changes = parse_changes(log_paths, groups, args.end)
    series = build_series(changes, args.start, args.end)

    write_assignments(groups, args.assignment_output)
    write_events(changes, args.events_output)
    write_series(series, args.series_output)

    print(f"validator_assignments={args.assignment_output} rows={len(groups.all_validators)}")
    print(f"validator_set_changes={args.events_output} rows={len(changes)}")
    print(f"validator_set_series={args.series_output} rows={len(series)}")
    print(
        "groups="
        f"V:{len(groups.baseline)} "
        f"candidate_V_A:{len(groups.candidate_a)} "
        f"candidate_V_B:{len(groups.candidate_b)} "
        f"all:{len(groups.all_validators)}"
    )
    print(f"logs={len(log_paths)}")


if __name__ == "__main__":
    main()
