//! `~/.claude/rc-dirs.txt`（自動起動の対象ディレクトリ一覧）の読み書き。
//!
//! 1 行 1 ディレクトリ。`#` 以降はコメント、空行は無視、`~` はホームに展開する。
//! 書き換えるときは登録行だけを足し引きして、コメントや並び順はそのまま残す。

use std::path::{Path, PathBuf};

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

pub fn path() -> PathBuf {
    match std::env::var_os("RC_DIRS_FILE") {
        Some(p) => PathBuf::from(p),
        None => home().join(".claude/rc-dirs.txt"),
    }
}

/// `~/foo` → `/Users/me/foo`
pub fn expand(s: &str) -> PathBuf {
    if s == "~" {
        home()
    } else if let Some(rest) = s.strip_prefix("~/") {
        home().join(rest)
    } else {
        PathBuf::from(s)
    }
}

/// `/Users/me/foo` → `~/foo`（表示と保存に使う）
pub fn shorten(p: &Path) -> String {
    match p.strip_prefix(home()) {
        Ok(rest) if !rest.as_os_str().is_empty() => format!("~/{}", rest.display()),
        _ => p.display().to_string(),
    }
}

/// 行から登録ディレクトリを取り出す。コメント行・空行は None。
fn parse_line(line: &str) -> Option<PathBuf> {
    let body = line.split('#').next().unwrap_or("").trim();
    if body.is_empty() { None } else { Some(expand(body)) }
}

fn read() -> Result<String, String> {
    let p = path();
    match std::fs::read_to_string(&p) {
        Ok(s) => Ok(s),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(String::new()),
        Err(e) => Err(format!("{} を読めません: {e}", p.display())),
    }
}

/// 登録されているディレクトリを、ファイルに書かれた順で返す。
pub fn entries() -> Result<Vec<PathBuf>, String> {
    Ok(read()?.lines().filter_map(parse_line).collect())
}

/// 追加する。既にあれば false を返して何も書かない。
pub fn add(dir: &Path) -> Result<bool, String> {
    if entries()?.iter().any(|e| e == dir) {
        return Ok(false);
    }
    let p = path();
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("{} を作れません: {e}", parent.display()))?;
    }
    let mut body = read()?;
    if !body.is_empty() && !body.ends_with('\n') {
        body.push('\n');
    }
    body.push_str(&shorten(dir));
    body.push('\n');
    std::fs::write(&p, body).map_err(|e| format!("{} に書けません: {e}", p.display()))?;
    Ok(true)
}

/// 削除する。登録されていなければ false を返す。コメント行はそのまま残す。
pub fn remove(dir: &Path) -> Result<bool, String> {
    let body = read()?;
    let mut removed = false;
    let kept: Vec<&str> = body
        .lines()
        .filter(|line| match parse_line(line) {
            Some(d) if d == dir => {
                removed = true;
                false
            }
            _ => true,
        })
        .collect();
    if !removed {
        return Ok(false);
    }
    let mut out = kept.join("\n");
    if !out.is_empty() {
        out.push('\n');
    }
    let p = path();
    std::fs::write(&p, out).map_err(|e| format!("{} に書けません: {e}", p.display()))?;
    Ok(true)
}
