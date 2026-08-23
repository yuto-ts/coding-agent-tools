//! 対話画面。登録ディレクトリと rc の起動状態を一覧し、その場で ON/OFF と追加・削除を行う。

use std::io::{IsTerminal, Write, stdout};
use std::path::PathBuf;
use std::time::Duration;

use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, poll, read};
use crossterm::style::{Attribute, Color, Print, ResetColor, SetAttribute, SetForegroundColor};
use crossterm::terminal::{Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode, size};
use crossterm::{cursor, execute, queue};

use crate::config;
use crate::picker;
use crate::rc::{self, Session};

const HELP: &str = "↑↓ 選択   Space ON/OFF   a Finderで追加   i パス入力で追加   d リストから削除   r 更新   q 終了";
const REFRESH: Duration = Duration::from_millis(3000);

struct Row {
    dir: PathBuf,
    listed: bool,
    session: Option<Session>,
}

enum Mode {
    Normal,
    /// パス入力中
    Input(String),
    /// 削除の確認
    Confirm(PathBuf),
}

struct App {
    rows: Vec<Row>,
    sel: usize,
    msg: String,
    mode: Mode,
}

impl App {
    fn new() -> Result<Self, String> {
        let mut app = App { rows: Vec::new(), sel: 0, msg: String::new(), mode: Mode::Normal };
        app.refresh()?;
        Ok(app)
    }

    /// 登録ディレクトリ（設定ファイルの順）＋ 未登録だが起動中のディレクトリ。
    fn refresh(&mut self) -> Result<(), String> {
        let sessions = rc::scan();
        let listed = config::entries()?;
        let mut rows: Vec<Row> = listed
            .iter()
            .map(|dir| Row {
                dir: dir.clone(),
                listed: true,
                session: rc::session_for(&sessions, dir).cloned(),
            })
            .collect();
        for s in &sessions {
            if !listed.iter().any(|d| d == &s.dir) {
                rows.push(Row { dir: s.dir.clone(), listed: false, session: Some(s.clone()) });
            }
        }
        self.rows = rows;
        if self.sel >= self.rows.len() {
            self.sel = self.rows.len().saturating_sub(1);
        }
        Ok(())
    }

    fn running(&self) -> usize {
        self.rows.iter().filter(|r| r.session.is_some()).count()
    }

    fn toggle(&mut self) {
        let Some(row) = self.rows.get(self.sel) else { return };
        let dir = row.dir.clone();
        let result = match &row.session {
            Some(s) => rc::stop(s).map(|_| format!("停止しました: {}", config::shorten(&dir))),
            None => rc::start(&dir).map(|name| format!("起動しました: {} ({name})", config::shorten(&dir))),
        };
        self.msg = match result {
            Ok(m) => m,
            Err(e) => format!("エラー: {e}"),
        };
        let _ = self.refresh();
    }

    fn add(&mut self, dir: PathBuf) {
        if !dir.is_dir() {
            self.msg = format!("エラー: ディレクトリがありません: {}", dir.display());
            return;
        }
        self.msg = match config::add(&dir) {
            Ok(true) => format!("追加しました: {}", config::shorten(&dir)),
            Ok(false) => format!("すでに登録されています: {}", config::shorten(&dir)),
            Err(e) => format!("エラー: {e}"),
        };
        let _ = self.refresh();
        if let Some(i) = self.rows.iter().position(|r| r.dir == dir) {
            self.sel = i;
        }
    }

    fn remove(&mut self, dir: &PathBuf) {
        self.msg = match config::remove(dir) {
            Ok(true) => format!("リストから削除しました: {}（起動中の rc はそのまま）", config::shorten(dir)),
            Ok(false) => format!("登録されていません: {}", config::shorten(dir)),
            Err(e) => format!("エラー: {e}"),
        };
        let _ = self.refresh();
    }
}

fn draw(app: &App) -> Result<(), String> {
    let mut out = stdout();
    let (_, rows_h) = size().unwrap_or((80, 24));
    queue!(out, Clear(ClearType::All), cursor::MoveTo(0, 0)).map_err(io)?;

    queue!(
        out,
        SetAttribute(Attribute::Bold),
        Print("  Claude Remote Control"),
        SetAttribute(Attribute::Reset),
        Print(format!("    {}/{} 起動中", app.running(), app.rows.len())),
    )
    .map_err(io)?;

    if app.rows.is_empty() {
        queue!(out, cursor::MoveTo(0, 2), Print("  登録されたディレクトリがありません。a か i で追加してください。")).map_err(io)?;
    }
    for (i, row) in app.rows.iter().enumerate() {
        let y = 2 + i as u16;
        if y + 3 >= rows_h {
            break;
        }
        let (mark, color) = match &row.session {
            Some(_) => ("●", Color::Green),
            None => ("○", Color::DarkGrey),
        };
        queue!(
            out,
            cursor::MoveTo(0, y),
            Print(if i == app.sel { "  ▸ " } else { "    " }),
            SetForegroundColor(color),
            Print(mark),
            ResetColor,
            Print(format!(" {:<40}", config::shorten(&row.dir))),
        )
        .map_err(io)?;
        if let Some(s) = &row.session {
            queue!(out, SetForegroundColor(Color::DarkGrey), Print(s.label()), ResetColor).map_err(io)?;
        }
        if !row.listed {
            queue!(out, SetForegroundColor(Color::Yellow), Print("  (未登録)"), ResetColor).map_err(io)?;
        }
    }

    let foot = rows_h.saturating_sub(2);
    match &app.mode {
        Mode::Normal => {
            queue!(out, cursor::MoveTo(0, foot), SetForegroundColor(Color::DarkGrey), Print(format!("  {HELP}")), ResetColor).map_err(io)?;
        }
        Mode::Input(buf) => {
            queue!(out, cursor::MoveTo(0, foot), Print(format!("  パス: {buf}_   （Enter 決定 / Esc 取消）"))).map_err(io)?;
        }
        Mode::Confirm(dir) => {
            queue!(
                out,
                cursor::MoveTo(0, foot),
                Print(format!("  {} をリストから削除しますか? (y/n)", config::shorten(dir)))
            )
            .map_err(io)?;
        }
    }
    if !app.msg.is_empty() {
        queue!(out, cursor::MoveTo(0, foot + 1), Print(format!("  {}", app.msg))).map_err(io)?;
    }
    out.flush().map_err(io)
}

fn io(e: std::io::Error) -> String {
    format!("端末の操作に失敗しました: {e}")
}

/// Finder を出す間だけ画面を明け渡す。
fn with_suspended_screen<T>(f: impl FnOnce() -> T) -> Result<T, String> {
    disable_raw_mode().map_err(io)?;
    execute!(stdout(), LeaveAlternateScreen).map_err(io)?;
    let result = f();
    execute!(stdout(), EnterAlternateScreen, cursor::Hide).map_err(io)?;
    enable_raw_mode().map_err(io)?;
    Ok(result)
}

fn handle_key(app: &mut App, key: KeyEvent) -> Result<bool, String> {
    if key.modifiers.contains(KeyModifiers::CONTROL) && matches!(key.code, KeyCode::Char('c')) {
        return Ok(false);
    }
    match &mut app.mode {
        Mode::Input(buf) => match key.code {
            KeyCode::Enter => {
                let raw = buf.trim().to_string();
                app.mode = Mode::Normal;
                if !raw.is_empty() {
                    let dir = config::expand(&raw);
                    let dir = dir.canonicalize().unwrap_or(dir);
                    app.add(dir);
                }
            }
            KeyCode::Esc => app.mode = Mode::Normal,
            KeyCode::Backspace => {
                buf.pop();
            }
            KeyCode::Char(c) => buf.push(c),
            _ => {}
        },
        Mode::Confirm(dir) => {
            let dir = dir.clone();
            match key.code {
                KeyCode::Char('y') | KeyCode::Char('Y') => {
                    app.mode = Mode::Normal;
                    app.remove(&dir);
                }
                KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => {
                    app.mode = Mode::Normal;
                    app.msg = "取り消しました".into();
                }
                _ => {}
            }
        }
        Mode::Normal => match key.code {
            KeyCode::Char('q') | KeyCode::Esc => return Ok(false),
            KeyCode::Up | KeyCode::Char('k') => app.sel = app.sel.saturating_sub(1),
            KeyCode::Down | KeyCode::Char('j') => {
                if app.sel + 1 < app.rows.len() {
                    app.sel += 1;
                }
            }
            KeyCode::Char(' ') | KeyCode::Enter => app.toggle(),
            KeyCode::Char('r') => {
                app.refresh()?;
                app.msg = "更新しました".into();
            }
            KeyCode::Char('i') => app.mode = Mode::Input(String::new()),
            KeyCode::Char('a') => {
                let start = app.rows.get(app.sel).map(|r| r.dir.clone()).unwrap_or_else(config::home);
                let picked = with_suspended_screen(|| picker::choose_folder("claude rc を動かすプロジェクトを選択", &start))?;
                match picked {
                    Ok(Some(dir)) => app.add(dir),
                    Ok(None) => app.msg = "キャンセルしました".into(),
                    Err(e) => app.msg = format!("エラー: {e}"),
                }
            }
            KeyCode::Char('d') => {
                if let Some(row) = app.rows.get(app.sel) {
                    if row.listed {
                        app.mode = Mode::Confirm(row.dir.clone());
                    } else {
                        app.msg = "そのディレクトリは登録されていません（Space で停止できます）".into();
                    }
                }
            }
            _ => {}
        },
    }
    Ok(true)
}

pub fn run() -> Result<(), String> {
    if !stdout().is_terminal() {
        return Err("対話画面には端末が必要です。`claude-rc --help` を見てください。".into());
    }
    let mut app = App::new()?;

    enable_raw_mode().map_err(io)?;
    execute!(stdout(), EnterAlternateScreen, cursor::Hide).map_err(io)?;

    let result = (|| -> Result<(), String> {
        loop {
            draw(&app)?;
            if poll(REFRESH).map_err(io)? {
                match read().map_err(io)? {
                    Event::Key(key) if key.kind == KeyEventKind::Press => {
                        if !handle_key(&mut app, key)? {
                            return Ok(());
                        }
                    }
                    _ => {}
                }
            } else if matches!(app.mode, Mode::Normal) {
                app.refresh()?;
            }
        }
    })();

    execute!(stdout(), cursor::Show, LeaveAlternateScreen).map_err(io)?;
    disable_raw_mode().map_err(io)?;
    result
}
