#!/usr/bin/env python3
"""AI調の日本語表現を検出する Claude Code hook。

4 つのモードを持つ:
  --hook pre-tool-use   Write/Edit の直前に、そのファイルに既にある違反を
                        「既存分」として記録する(セッション中の初回のみ)
  --hook post-tool-use  Write/Edit 直後に書き込まれたファイルを検査し、
                        既存分を超えた違反があれば exit 2 で書き直しを求める
  --hook stop           セッション終了時に、そのセッションで編集した全ファイルを
                        再検査し、違反が残っていれば終了をブロックする
  <file>...             手動検査(ルール追加時のテスト用)。違反があれば exit 1

検査は 2 層:
  1. rules.jsonl の NG ワード照合(正規表現、行単位)。各ルールは
     グッドパターン(書き直し例)を持ち、警告と一緒に返す
  2. 文書全体の集計 — 同一文末の 3 文以上の連続、です・ます調と常体の混在

エージェントが書いていない既存の文を直させないため、検出は「そのセッションが
そのファイルに触る前からあった違反」を差し引いた超過分だけを報告する。
差し引きは行番号ではなく (ルール, 一致文字列) の指紋で数えるので、
編集で行がずれても既存分は既存分のまま扱われる。

ファイル先頭付近に「ai-writing-check: off」と書かれたファイルは検査しない
(NG 例を引用するスタイルガイドなど向け)。
"""

import json
import os
import re
import sys
import time
from collections import Counter

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
# state はリポジトリ外に置く(SCRIPT_DIR は通常リポジトリ内の実体を指すため)
STATE_DIR = os.path.expanduser("~/.cache/ai-writing-check")
STATE_TTL = 7 * 24 * 3600
TEXT_EXTS = (".md", ".mdx", ".txt")
WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
OFF_MARKER = "ai-writing-check: off"
JA = re.compile(r"[ぁ-んァ-ヶ]")
MAX_LISTED = 30

FENCE = re.compile(r"^\s*(```|~~~)")
LIST_ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s")
INLINE_CODE = re.compile(r"`[^`]*`")
KAGI_QUOTE = re.compile(r"「[^」]*」")

# 文末の分類(長い順に照合する)
POLITE_SUFFIXES = [
    "ませんでした", "いたします", "ください", "ましょう", "でしょう",
    "ました", "ません", "でした", "です", "ます",
]
# 連続検出の対象にする文末(体言止めや稀な語尾は対象外)
RUN_SUFFIXES = sorted(
    POLITE_SUFFIXES + ["である", "だった", "できる", "した", "する", "だ"],
    key=len, reverse=True,
)
RUN_MIN = 3


def match_suffix(sentence, suffixes):
    for suf in suffixes:
        if sentence.endswith(suf):
            return suf
    return None


def load_rules():
    """rules.jsonl(スクリプトと同じディレクトリ)と、あれば
    $CLAUDE_PROJECT_DIR/.claude/ai-writing-rules.jsonl を読む。"""
    paths = [os.path.join(SCRIPT_DIR, "rules.jsonl")]
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    if project_dir:
        paths.append(os.path.join(project_dir, ".claude", "ai-writing-rules.jsonl"))

    rules = []
    for path in paths:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            for lineno, raw in enumerate(f, 1):
                raw = raw.strip()
                if not raw or raw.startswith("#"):
                    continue
                try:
                    rule = json.loads(raw)
                    rule["_re"] = re.compile(rule["pattern"])
                    rules.append(rule)
                except (json.JSONDecodeError, re.error, KeyError) as e:
                    print(f"[ai-writing-check] ルール読み込み失敗 {path}:{lineno}: {e}",
                          file=sys.stderr)
    return rules


def iter_prose_lines(text):
    """コードフェンスの外側の行だけを (行番号, 行) で返す。"""
    in_fence = False
    for lineno, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield lineno, line


def check_words(content, rules):
    violations = []
    for lineno, line in iter_prose_lines(content):
        stripped = line.strip()
        if stripped.startswith(">"):
            continue
        body = INLINE_CODE.sub("", line)
        for rule in rules:
            for m in rule["_re"].finditer(body):
                violations.append({
                    "line": lineno,
                    "label": f"「{m.group(0)}」",
                    "fix": rule.get("good", "文脈に合う具体的な表現に書き直す"),
                    # 指紋は行番号を含めない。編集で行がずれても同一とみなすため
                    "fp": f"w|{rule.get('id', rule['pattern'])}|{m.group(0)}",
                })
    return violations


def analyze_endings(content):
    """文末を集計する。返り値: (run_seq, polite_lines, plain_lines)

    run_seq は文の並び。(行番号, 正規化した文末 or None)。
    None は段落・見出し・箇条書きなどの区切りで、連続カウントをリセットする。
    """
    run_seq = []
    polite_lines = []
    plain_lines = []
    for lineno, raw in iter_prose_lines(content):
        s = raw.strip()
        if not s or s.startswith((">", "#", "|")):
            run_seq.append((lineno, None))
            continue
        is_list = bool(LIST_ITEM.match(raw))
        body = KAGI_QUOTE.sub("", INLINE_CODE.sub("", s))
        for m in re.finditer(r"[^。]+。", body):
            sent = m.group(0)[:-1].strip().rstrip("」』）)\"'")
            if not sent or not JA.search(sent):
                continue
            polite = match_suffix(sent, POLITE_SUFFIXES)
            if polite:
                polite_lines.append(lineno)
            elif re.search(r"[ぁ-ん]$", sent):
                plain_lines.append(lineno)
            # 箇条書きは文末が揃うのが普通なので連続カウントの対象外
            run_suffix = None if is_list else match_suffix(sent, RUN_SUFFIXES)
            run_seq.append((lineno, run_suffix))
    return run_seq, polite_lines, plain_lines


def find_runs(run_seq):
    runs = []
    cur, count, start, last = None, 0, None, None
    for lineno, suf in run_seq:
        if suf is not None and suf == cur:
            count += 1
            last = lineno
        else:
            if cur is not None and count >= RUN_MIN:
                runs.append((cur, count, start, last))
            cur, count, start, last = suf, (1 if suf else 0), lineno, lineno
    if cur is not None and count >= RUN_MIN:
        runs.append((cur, count, start, last))
    return runs


def check_document(content):
    violations = []
    run_seq, polite_lines, plain_lines = analyze_endings(content)

    for suffix, count, start, last in find_runs(run_seq):
        loc = f"L{start}" if start == last else f"L{start}-L{last}"
        violations.append({
            "line": start,
            "label": f"文末「{suffix}。」が {count} 文連続({loc})",
            "fix": "文末の形を変えるか、文を統合して単調さをなくす",
            "fp": f"run|{suffix}",
        })

    if len(polite_lines) >= 2 and len(plain_lines) >= 2:
        minority = plain_lines if len(plain_lines) <= len(polite_lines) else polite_lines
        name = "常体" if minority is plain_lines else "です・ます調"
        examples = ", ".join(f"L{n}" for n in dict.fromkeys(minority[:6]))
        violations.append({
            "line": minority[0],
            "label": (f"です・ます調({len(polite_lines)} 文)と"
                      f"常体({len(plain_lines)} 文)が混在"),
            "fix": f"どちらかに統一する(少数派は {name}: {examples})",
            "fp": "mix",
        })
    return violations


def is_target(path):
    if not path or not path.lower().endswith(TEXT_EXTS):
        return False
    return os.path.isfile(path)


def check_file(path, rules):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError:
        return []
    if OFF_MARKER in content:
        return []
    if not JA.search(content):
        return []
    violations = check_words(content, rules) + check_document(content)
    for v in violations:
        v["file"] = path
    return sorted(violations, key=lambda v: (v["file"], v["line"]))


def state_path(session_id):
    sid = re.sub(r"[^A-Za-z0-9_-]", "_", session_id or "unknown")
    return os.path.join(STATE_DIR, sid + ".json")


def load_state(session_id):
    """{ファイルパス: {指紋: 件数}} を返す。"""
    try:
        with open(state_path(session_id), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(session_id, state):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(state_path(session_id), "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
    except OSError:
        pass


def prune_state():
    """古いセッションの state を消す。"""
    try:
        now = time.time()
        for name in os.listdir(STATE_DIR):
            p = os.path.join(STATE_DIR, name)
            if now - os.path.getmtime(p) > STATE_TTL:
                os.remove(p)
    except OSError:
        pass


def baseline_of(path, rules):
    """今そのファイルにある違反を {指紋: 件数} で返す。"""
    return dict(Counter(v["fp"] for v in check_file(path, rules)))


def subtract_baseline(violations, baseline):
    """既存分(baseline)を件数分だけ差し引き、超過分だけ返す。"""
    if not baseline:
        return violations
    seen = Counter()
    out = []
    for v in violations:
        fp = v.get("fp", "")
        seen[fp] += 1
        if seen[fp] <= baseline.get(fp, 0):
            continue  # 触る前からあった違反
        out.append(v)
    return out


def format_report(violations, closing):
    lines = ["[ai-writing-check] AI調の表現を検出しました。", ""]
    for v in violations[:MAX_LISTED]:
        lines.append(f"{v['file']}:{v['line']}: {v['label']}")
        lines.append(f"  → {v['fix']}")
    if len(violations) > MAX_LISTED:
        lines.append(f"...ほか {len(violations) - MAX_LISTED} 件")
    lines.append("")
    lines.append(closing)
    return "\n".join(lines) + "\n"

REWRITE_RULE = ("修正方法: 該当語だけを別の語に置き換えることは禁止。"
                "検出箇所を含む文を丸ごと書き直すこと。書き直した内容も再検査される。")


def target_path(data):
    tool_input = data.get("tool_input") or {}
    return tool_input.get("file_path") or tool_input.get("notebook_path")


def hook_pre_tool_use():
    """書き込む前の違反を「既存分」として記録する(そのセッションの初回のみ)。"""
    data = json.load(sys.stdin)
    path = target_path(data)
    if not path or not path.lower().endswith(TEXT_EXTS):
        return 0
    session_id = data.get("session_id")
    state = load_state(session_id)
    if path in state:
        return 0  # 2 回目以降。エージェント自身の違反を既存分にしない
    # ファイルがまだ無ければ新規作成 = 全部そのセッションの責任
    state[path] = baseline_of(path, load_rules()) if os.path.isfile(path) else {}
    prune_state()
    save_state(session_id, state)
    return 0


def hook_post_tool_use():
    data = json.load(sys.stdin)
    path = target_path(data)
    if not is_target(path):
        return 0
    baseline = load_state(data.get("session_id")).get(path, {})
    violations = subtract_baseline(check_file(path, load_rules()), baseline)
    if not violations:
        return 0
    sys.stderr.write(format_report(violations, REWRITE_RULE))
    return 2


def collect_edited_files(transcript_path):
    """transcript(JSONL)から Write/Edit 系ツールの対象ファイルを集める。"""
    files = []
    if not transcript_path or not os.path.isfile(transcript_path):
        return files

    def walk(node):
        if isinstance(node, dict):
            if node.get("type") == "tool_use" and node.get("name") in WRITE_TOOLS:
                fp = (node.get("input") or {}).get("file_path") \
                    or (node.get("input") or {}).get("notebook_path")
                if fp and fp not in files:
                    files.append(fp)
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    with open(transcript_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                walk(json.loads(line))
            except json.JSONDecodeError:
                continue
    return files


def hook_stop():
    data = json.load(sys.stdin)
    session_id = data.get("session_id")
    if data.get("stop_hook_active"):
        # 一度ブロック済み。直せない違反で終了できなくなるのを防ぐ
        return 0
    rules = load_rules()
    state = load_state(session_id)
    violations = []
    for path in collect_edited_files(data.get("transcript_path")):
        if is_target(path):
            violations.extend(
                subtract_baseline(check_file(path, rules), state.get(path, {})))
    if not violations:
        try:
            os.remove(state_path(session_id))
        except OSError:
            pass
        return 0
    sys.stderr.write(format_report(
        violations,
        "違反が残っているため作業を完了できない。" + REWRITE_RULE))
    return 2


def cli(paths):
    rules = load_rules()
    violations = []
    for path in paths:
        if os.path.isfile(path):
            violations.extend(check_file(path, rules))
        else:
            print(f"[ai-writing-check] ファイルが見つかりません: {path}", file=sys.stderr)
    if not violations:
        print("違反はありません。")
        return 0
    sys.stdout.write(format_report(violations, REWRITE_RULE))
    return 1


def main():
    args = sys.argv[1:]
    try:
        if len(args) >= 2 and args[0] == "--hook":
            if args[1] == "pre-tool-use":
                return hook_pre_tool_use()
            if args[1] == "post-tool-use":
                return hook_post_tool_use()
            if args[1] == "stop":
                return hook_stop()
            print(f"[ai-writing-check] 不明な hook: {args[1]}", file=sys.stderr)
            return 0
        if args:
            return cli(args)
        print(__doc__, file=sys.stderr)
        return 0
    except Exception as e:  # hook の内部エラーでセッションを壊さない
        print(f"[ai-writing-check] 内部エラー: {e}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main())
