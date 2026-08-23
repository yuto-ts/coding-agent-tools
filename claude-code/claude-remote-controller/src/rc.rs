//! `claude rc` の状態検出と起動・停止。
//!
//! 起動は detached な tmux セッションの中で行う。`claude rc` は TUI なので PTY が要り、
//! launchd から直接起動できないため。副作用として、あとから `tmux attach` で
//! 接続 URL や QR コードを見られる。

use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Origin {
    /// このツールが作った tmux セッション
    Tmux(String),
    /// 別のターミナルで手動起動されたプロセス
    External(u32),
}

#[derive(Debug, Clone)]
pub struct Session {
    pub dir: PathBuf,
    pub origin: Origin,
}

impl Session {
    pub fn label(&self) -> String {
        match &self.origin {
            Origin::Tmux(name) => format!("tmux:{name}"),
            Origin::External(pid) => format!("外部 pid {pid}"),
        }
    }
}

fn find_bin(name: &str, env_override: &str, fallbacks: &[&str]) -> Result<PathBuf, String> {
    if let Some(p) = std::env::var_os(env_override) {
        let p = PathBuf::from(p);
        if p.is_file() {
            return Ok(p);
        }
    }
    // launchd から起動されると PATH は /usr/bin:/bin:/usr/sbin:/sbin しかないので、
    // 見つからなければ既知のインストール先も見る。
    if let Some(paths) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&paths) {
            let cand = dir.join(name);
            if cand.is_file() {
                return Ok(cand);
            }
        }
    }
    for f in fallbacks {
        let cand = crate::config::expand(f);
        if cand.is_file() {
            return Ok(cand);
        }
    }
    Err(format!("{name} が見つかりません（{env_override} で指定できます）"))
}

pub fn tmux_bin() -> Result<PathBuf, String> {
    find_bin("tmux", "TMUX_BIN", &["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"])
}

pub fn claude_bin() -> Result<PathBuf, String> {
    find_bin("claude", "CLAUDE_BIN", &["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
}

fn output(cmd: &mut Command) -> Result<String, String> {
    let out = cmd.output().map_err(|e| format!("{:?} を実行できません: {e}", cmd.get_program()))?;
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// tmux セッションのうち、このツールが作ったもの（`rc-` 始まり）を返す。
fn tmux_sessions() -> Vec<(String, PathBuf)> {
    let Ok(tmux) = tmux_bin() else { return Vec::new() };
    // tmux サーバが動いていなければエラー終了するが、それは「0 セッション」と同じ扱いでよい。
    // tmux はコマンド出力の制御文字を潰す（タブ区切りにすると `_` になる）ので、区切り文字は
    // 置かずに「セッション名に / は入らない」「session_path は絶対パス」ことを使って最初の / で切る。
    let stdout = output(Command::new(tmux).args(["list-sessions", "-F", "#{session_name}#{session_path}"]))
        .unwrap_or_default();
    stdout
        .lines()
        .filter_map(|line| line.split_once('/'))
        .filter(|(name, _)| name.starts_with("rc-"))
        .map(|(name, path)| (name.to_string(), PathBuf::from(format!("/{path}"))))
        .collect()
}

/// tmux の外で手動起動された `claude rc` を、プロセスの cwd 付きで返す。
fn external_sessions() -> Vec<(u32, PathBuf)> {
    let pids = output(Command::new("pgrep").args(["-f", "claude (rc|remote-control)"])).unwrap_or_default();
    let mut found = Vec::new();
    for pid in pids.lines().filter_map(|l| l.trim().parse::<u32>().ok()) {
        // pgrep -f は `tmux new-session ... claude rc` のような起動側にも当たるので、
        // 実行ファイルが claude 本体のものだけ残す。
        let comm = output(Command::new("ps").args(["-o", "comm=", "-p", &pid.to_string()])).unwrap_or_default();
        if Path::new(comm.trim()).file_name().and_then(|s| s.to_str()) != Some("claude") {
            continue;
        }
        let lsof = output(Command::new("lsof").args(["-a", "-p", &pid.to_string(), "-d", "cwd", "-Fn"])).unwrap_or_default();
        if let Some(cwd) = lsof.lines().find_map(|l| l.strip_prefix('n')) {
            found.push((pid, PathBuf::from(cwd)));
        }
    }
    found
}

/// いま rc が動いているディレクトリの一覧。tmux 管理ぶんを優先し、同じ cwd の外部プロセスは重複させない。
pub fn scan() -> Vec<Session> {
    let mut sessions: Vec<Session> = tmux_sessions()
        .into_iter()
        .map(|(name, dir)| Session { dir, origin: Origin::Tmux(name) })
        .collect();
    for (pid, dir) in external_sessions() {
        if !sessions.iter().any(|s| s.dir == dir) {
            sessions.push(Session { dir, origin: Origin::External(pid) });
        }
    }
    sessions
}

pub fn session_for<'a>(sessions: &'a [Session], dir: &Path) -> Option<&'a Session> {
    sessions.iter().find(|s| s.dir == dir)
}

fn session_name_for(dir: &Path) -> String {
    let base: String = dir
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("root")
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    format!("rc-{}", if base.is_empty() { "root".to_string() } else { base })
}

/// そのディレクトリで `claude rc` を起動し、作った tmux セッション名を返す。
pub fn start(dir: &Path) -> Result<String, String> {
    if !dir.is_dir() {
        return Err(format!("ディレクトリがありません: {}", dir.display()));
    }
    if let Some(s) = session_for(&scan(), dir) {
        return Err(format!("すでに起動しています（{}）", s.label()));
    }
    let tmux = tmux_bin()?;
    let claude = claude_bin()?;
    let existing = tmux_sessions();

    let mut name = session_name_for(dir);
    if existing.iter().any(|(n, _)| *n == name) {
        // 別ディレクトリで同じ basename を使っている場合
        name = (2..100)
            .map(|i| format!("{name}-{i}"))
            .find(|cand| !existing.iter().any(|(n, _)| n == cand))
            .ok_or_else(|| format!("セッション名が埋まっています: {name}"))?;
    }

    let status = Command::new(&tmux)
        .args(["new-session", "-d", "-s", &name, "-c"])
        .arg(dir)
        .arg(&claude)
        .arg("rc")
        .status()
        .map_err(|e| format!("tmux を実行できません: {e}"))?;
    if !status.success() {
        return Err(format!("tmux new-session が失敗しました（{}）", dir.display()));
    }
    Ok(name)
}

/// 起動中の rc を止める。tmux 管理ぶんはセッションごと、外部プロセスは SIGTERM。
pub fn stop(session: &Session) -> Result<(), String> {
    match &session.origin {
        Origin::Tmux(name) => {
            let tmux = tmux_bin()?;
            let status = Command::new(tmux)
                .args(["kill-session", "-t", &format!("={name}")])
                .status()
                .map_err(|e| format!("tmux を実行できません: {e}"))?;
            if status.success() { Ok(()) } else { Err(format!("tmux kill-session が失敗しました: {name}")) }
        }
        Origin::External(pid) => {
            let status = Command::new("kill")
                .args(["-TERM", &pid.to_string()])
                .status()
                .map_err(|e| format!("kill を実行できません: {e}"))?;
            if status.success() { Ok(()) } else { Err(format!("pid {pid} を停止できませんでした")) }
        }
    }
}
