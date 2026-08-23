//! Claude Code の Remote Control (`claude rc`) をディレクトリ単位で管理する CLI。
//!
//! 引数なしで対話画面、`up` は launchd から叩かれる冪等な一括起動。

mod agent;
mod config;
mod picker;
mod rc;
mod ui;

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const USAGE: &str = "\
claude-rc — Claude Code の Remote Control (claude rc) を管理する

使い方:
  claude-rc              対話画面（一覧 / ON・OFF / 追加・削除）
  claude-rc up           登録ディレクトリのうち未起動のものを起動（冪等、launchd 用）
  claude-rc list         一覧を表示
  claude-rc on  <dir>    起動
  claude-rc off <dir>    停止
  claude-rc add [dir]    リストに追加（省略時は Finder で選ぶ）
  claude-rc rm  <dir>    リストから削除
  claude-rc setup        ログイン時の自動起動（LaunchAgent）を登録・更新する
  claude-rc setup --off  自動起動を解除する

環境変数:
  RC_DIRS_FILE       対象ディレクトリの一覧  (既定: ~/.claude/rc-dirs.txt)
  RC_LOG             up のログ               (既定: ~/.claude/rc-autostart.log)
  RC_CHECK_INTERVAL  自動起動の確認間隔・秒  (既定: 600)
  RC_LAUNCH_LABEL    LaunchAgent の Label    (既定: com.<ユーザ名>.claude-rc)
  CLAUDE_BIN         claude の絶対パス       (既定: PATH と既知の場所から探す)
  TMUX_BIN           tmux の絶対パス         (既定: 同上)
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        None => ui::run(),
        Some("up") => cmd_up(),
        Some("list") | Some("ls") => cmd_list(),
        Some("on") => cmd_on(args.get(1)),
        Some("off") => cmd_off(args.get(1)),
        Some("add") => cmd_add(args.get(1)),
        Some("rm") | Some("remove") => cmd_rm(args.get(1)),
        Some("setup") => match args.get(1).map(String::as_str) {
            None => agent::install(),
            Some("--off") | Some("--uninstall") => agent::uninstall(),
            Some(other) => Err(format!("setup の不明なオプション: {other}\n\n{USAGE}")),
        },
        Some("-h") | Some("--help") | Some("help") => {
            print!("{USAGE}");
            Ok(())
        }
        Some(other) => Err(format!("不明なサブコマンド: {other}\n\n{USAGE}")),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(msg) => {
            eprintln!("{msg}");
            ExitCode::FAILURE
        }
    }
}

fn arg_dir(arg: Option<&String>) -> Result<PathBuf, String> {
    let raw = arg.ok_or_else(|| format!("ディレクトリを指定してください\n\n{USAGE}"))?;
    let dir = config::expand(raw);
    Ok(dir.canonicalize().unwrap_or(dir))
}

fn now() -> String {
    Command::new("date")
        .arg("+%F %T")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn log_path() -> PathBuf {
    match std::env::var_os("RC_LOG") {
        Some(p) => PathBuf::from(p),
        None => config::home().join(".claude/rc-autostart.log"),
    }
}

fn log(line: &str) {
    use std::io::Write;
    let path = log_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(f, "{} {}", now(), line);
    }
}

/// 登録ディレクトリのうち動いていないものを起動する。何度実行しても副作用はない。
fn cmd_up() -> Result<(), String> {
    let sessions = rc::scan();
    let mut started = 0;
    for dir in config::entries()? {
        if rc::session_for(&sessions, &dir).is_some() {
            continue;
        }
        if !dir.is_dir() {
            log(&format!("skip (no such dir) {}", dir.display()));
            continue;
        }
        match rc::start(&dir) {
            Ok(name) => {
                log(&format!("started {name} in {}", dir.display()));
                started += 1;
            }
            Err(e) => log(&format!("FAILED {}: {e}", dir.display())),
        }
    }
    if started > 0 {
        println!("{started} 個起動しました");
    }
    Ok(())
}

fn cmd_list() -> Result<(), String> {
    let sessions = rc::scan();
    let listed = config::entries()?;
    let mut shown: Vec<&Path> = Vec::new();

    for dir in &listed {
        match rc::session_for(&sessions, dir) {
            Some(s) => println!("● {:<40} {}", config::shorten(dir), s.label()),
            None => println!("○ {}", config::shorten(dir)),
        }
        shown.push(dir);
    }
    for s in &sessions {
        if !shown.iter().any(|d| *d == s.dir) {
            println!("● {:<40} {}  (未登録)", config::shorten(&s.dir), s.label());
        }
    }
    if listed.is_empty() && sessions.is_empty() {
        println!("登録も起動もされていません（claude-rc add で追加）");
    }
    Ok(())
}

fn cmd_on(arg: Option<&String>) -> Result<(), String> {
    let dir = arg_dir(arg)?;
    let name = rc::start(&dir)?;
    println!("起動しました: {} ({name})", config::shorten(&dir));
    Ok(())
}

fn cmd_off(arg: Option<&String>) -> Result<(), String> {
    let dir = arg_dir(arg)?;
    let sessions = rc::scan();
    let session = rc::session_for(&sessions, &dir)
        .ok_or_else(|| format!("起動していません: {}", config::shorten(&dir)))?;
    rc::stop(session)?;
    println!("停止しました: {}", config::shorten(&dir));
    Ok(())
}

fn cmd_add(arg: Option<&String>) -> Result<(), String> {
    let dir = match arg {
        Some(_) => arg_dir(arg)?,
        None => match picker::choose_folder("claude rc を動かすプロジェクトを選択", &config::home())? {
            Some(dir) => dir,
            None => {
                println!("キャンセルしました");
                return Ok(());
            }
        },
    };
    if !dir.is_dir() {
        return Err(format!("ディレクトリがありません: {}", dir.display()));
    }
    if config::add(&dir)? {
        println!("追加しました: {}", config::shorten(&dir));
    } else {
        println!("すでに登録されています: {}", config::shorten(&dir));
    }
    Ok(())
}

fn cmd_rm(arg: Option<&String>) -> Result<(), String> {
    let dir = arg_dir(arg)?;
    if config::remove(&dir)? {
        println!("リストから削除しました: {}（起動中の rc はそのまま）", config::shorten(&dir));
    } else {
        println!("登録されていません: {}", config::shorten(&dir));
    }
    Ok(())
}
