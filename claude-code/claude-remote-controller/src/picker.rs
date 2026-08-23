//! Finder（macOS の標準ダイアログ）でディレクトリを選ぶ。

use std::path::{Path, PathBuf};
use std::process::Command;

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

/// キャンセルされたら Ok(None)。
pub fn choose_folder(prompt: &str, default_location: &Path) -> Result<Option<PathBuf>, String> {
    let mut script = format!("POSIX path of (choose folder with prompt \"{}\"", escape(prompt));
    if default_location.is_dir() {
        script.push_str(&format!(
            " default location POSIX file \"{}\"",
            escape(&default_location.display().to_string())
        ));
    }
    script.push(')');

    let out = Command::new("osascript")
        .arg("-e")
        .arg("activate") // ダイアログをターミナルの前面に出す
        .arg("-e")
        .arg(&script)
        .output()
        .map_err(|e| format!("osascript を実行できません: {e}"))?;

    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        // -128 = User canceled。ダイアログを外から閉じられた場合は stderr が空になる。
        if err.trim().is_empty() || err.contains("-128") || err.to_lowercase().contains("cancel") {
            return Ok(None);
        }
        return Err(format!("Finder での選択に失敗しました: {}", err.trim()));
    }

    let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if path.is_empty() {
        return Ok(None);
    }
    // choose folder の返り値は末尾に / が付く
    Ok(Some(PathBuf::from(path.trim_end_matches('/'))))
}
