//! LaunchAgent（ログイン時と一定間隔で `claude-rc up` を叩く）の登録と解除。
//!
//! `cargo install` でバイナリを置いたあと、`claude-rc setup` でここを実行する。

use std::path::PathBuf;
use std::process::Command;

use crate::config;

/// `~/.claude/rc-dirs.txt` が無いときに書く雛形。リポジトリの rc-dirs.example.txt をそのまま埋め込む。
const EXAMPLE_DIRS: &str = include_str!("../rc-dirs.example.txt");

fn uid() -> Result<String, String> {
    let out = Command::new("id").arg("-u").output().map_err(|e| format!("id を実行できません: {e}"))?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn username() -> String {
    Command::new("id")
        .arg("-un")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "user".to_string())
}

pub fn label() -> String {
    std::env::var("RC_LAUNCH_LABEL").unwrap_or_else(|_| format!("com.{}.claude-rc", username()))
}

fn plist_path(label: &str) -> PathBuf {
    config::home().join(format!("Library/LaunchAgents/{label}.plist"))
}

fn interval() -> u32 {
    std::env::var("RC_CHECK_INTERVAL").ok().and_then(|s| s.parse().ok()).unwrap_or(600)
}

/// 読み込まれていないものを bootout すると launchctl がエラーを出すが、それは想定内なので
/// 出力は飲み込んで成否だけ返す。
fn launchctl(args: &[&str]) -> Result<bool, String> {
    let out = Command::new("launchctl")
        .args(args)
        .output()
        .map_err(|e| format!("launchctl を実行できません: {e}"))?;
    Ok(out.status.success())
}

/// LaunchAgent を書いて読み込み直す。設定ファイルが無ければ雛形も置く。
pub fn install() -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| format!("自分のパスが分かりません: {e}"))?;
    let label = label();
    let plist = plist_path(&label);
    let uid = uid()?;
    let home = config::home();

    let conf = config::path();
    if !conf.exists() {
        if let Some(parent) = conf.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("{} を作れません: {e}", parent.display()))?;
        }
        std::fs::write(&conf, EXAMPLE_DIRS).map_err(|e| format!("{} に書けません: {e}", conf.display()))?;
        println!("作成しました: {}", config::shorten(&conf));
    }

    let body = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{exe}</string>
        <string>up</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>{interval}</integer>
    <key>StandardOutPath</key>
    <string>{home}/.claude/rc-autostart.out.log</string>
    <key>StandardErrorPath</key>
    <string>{home}/.claude/rc-autostart.err.log</string>
</dict>
</plist>
"#,
        label = label,
        exe = exe.display(),
        interval = interval(),
        home = home.display(),
    );

    if let Some(parent) = plist.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("{} を作れません: {e}", parent.display()))?;
    }
    std::fs::write(&plist, body).map_err(|e| format!("{} に書けません: {e}", plist.display()))?;
    println!("書き込みました: {}", config::shorten(&plist));

    // 既に読み込まれていれば入れ替える
    let _ = launchctl(&["bootout", &format!("gui/{uid}/{label}")]);
    if !launchctl(&["bootstrap", &format!("gui/{uid}"), &plist.display().to_string()])? {
        return Err(format!("launchctl bootstrap に失敗しました: {}", plist.display()));
    }
    println!("登録しました: {label}（ログイン時 + {} 秒ごとに {} up）", interval(), exe.display());
    Ok(())
}

/// LaunchAgent を外して plist を消す。rc セッションと設定ファイルはそのまま。
pub fn uninstall() -> Result<(), String> {
    let label = label();
    let plist = plist_path(&label);
    let uid = uid()?;

    if launchctl(&["bootout", &format!("gui/{uid}/{label}")])? {
        println!("解除しました: {label}");
    } else {
        println!("読み込まれていませんでした: {label}");
    }
    match std::fs::remove_file(&plist) {
        Ok(()) => println!("削除しました: {}", config::shorten(&plist)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(format!("{} を消せません: {e}", plist.display())),
    }
    println!("起動中の rc はそのままです（止めるなら claude-rc off <dir>）");
    Ok(())
}
