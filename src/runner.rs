//! Process execution helpers shared by action handlers.

use anyhow::{bail, Result};
use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};

/// Global dry-run toggle for command execution.
static DRY_RUN: AtomicBool = AtomicBool::new(false);

/// Enables or disables global dry-run mode.
pub fn set_dry_run(enabled: bool) {
    DRY_RUN.store(enabled, Ordering::Relaxed);
}

/// Returns whether global dry-run mode is active.
pub fn is_dry_run() -> bool {
    DRY_RUN.load(Ordering::Relaxed)
}

/// Runs a process and streams stdio; in dry-run mode only prints the command.
pub fn run(program: &str, args: &[&str]) -> Result<()> {
    let rendered = render_command(program, args);

    if is_dry_run() {
        println!("[termux-setmeup] dry-run: {}", rendered);
        return Ok(());
    }

    let mut cmd = Command::new(program);
    cmd.args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    let status = cmd.status().map_err(|err| {
        if err.kind() == std::io::ErrorKind::NotFound {
            anyhow::anyhow!("command not found in PATH: {}", program)
        } else {
            anyhow::anyhow!("failed to run command {}: {}", rendered, err)
        }
    })?;

    if !status.success() {
        bail!(
            "command failed (exit={}): {}",
            status
                .code()
                .map(|code| code.to_string())
                .unwrap_or_else(|| "signal".to_string()),
            rendered
        );
    }

    Ok(())
}

/// Runs a process with owned argument strings.
pub fn run_owned(program: &str, args: &[String]) -> Result<()> {
    let borrowed = args.iter().map(String::as_str).collect::<Vec<_>>();
    run(program, &borrowed)
}

/// Runs a process and writes `input` into its stdin.
pub fn run_with_stdin(program: &str, args: &[String], input: &[u8]) -> Result<()> {
    let borrowed = args.iter().map(String::as_str).collect::<Vec<_>>();
    let rendered = render_command(program, &borrowed);

    if is_dry_run() {
        println!("[termux-setmeup] dry-run: {} <stdin-bytes:{}>", rendered, input.len());
        return Ok(());
    }

    let mut cmd = Command::new(program);
    cmd.args(&borrowed)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    let mut child = cmd.spawn().map_err(|err| {
        if err.kind() == std::io::ErrorKind::NotFound {
            anyhow::anyhow!("command not found in PATH: {}", program)
        } else {
            anyhow::anyhow!("failed to run command {}: {}", rendered, err)
        }
    })?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(input)
            .map_err(|err| anyhow::anyhow!("failed to write stdin for {}: {}", rendered, err))?;
    }

    let status = child
        .wait()
        .map_err(|err| anyhow::anyhow!("failed to wait for command {}: {}", rendered, err))?;

    if !status.success() {
        bail!(
            "command failed (exit={}): {}",
            status
                .code()
                .map(|code| code.to_string())
                .unwrap_or_else(|| "signal".to_string()),
            rendered
        );
    }

    Ok(())
}

/// Renders a process invocation for logging and error output.
fn render_command(program: &str, args: &[&str]) -> String {
    if args.is_empty() {
        program.to_string()
    } else {
        format!("{} {}", program, args.join(" "))
    }
}
