//! High-level actions invoked by CLI options.

use crate::runner;
use anyhow::{Context, Result};
use reqwest::blocking::Client;
use serde::Deserialize;
use std::fs::{self, File};
use std::io::copy;
use std::time::{SystemTime, UNIX_EPOCH};

const EMBEDDED_EXTRA_PACKAGES: &str = include_str!("../res/extra-packages.txt");
const EMBEDDED_APT_TWEAKS: &str = include_str!("../res/my-apt.conf");

#[derive(Debug, Deserialize)]
/// Subset of F-Droid package metadata needed to resolve latest Termux APK.
struct FdroidPackageMeta {
    #[serde(rename = "suggestedVersionCode")]
    suggested_version_code: u64,
}

/// Downloads the latest Termux APK from F-Droid and installs it via `adb`.
pub fn adb_install_termux() -> Result<()> {
    if runner::is_dry_run() {
        println!("[termux-setmeup] dry-run: would download latest Termux APK from F-Droid");
        runner::run("adb", &["install", "-r", "<termux-apk-path>"])?;
        return Ok(());
    }

    let client = Client::builder()
        .user_agent("termux-setmeup")
        .build()
        .context("failed to build HTTP client")?;

    let metadata_url = "https://f-droid.org/api/v1/packages/com.termux";
    let meta: FdroidPackageMeta = client
        .get(metadata_url)
        .send()
        .context("failed to fetch F-Droid metadata")?
        .error_for_status()
        .context("F-Droid metadata request failed")?
        .json()
        .context("failed to parse F-Droid metadata JSON")?;

    let version_code = meta.suggested_version_code;
    let apk_name = format!("com.termux_{}.apk", version_code);
    let apk_url = format!("https://f-droid.org/repo/{}", apk_name);

    let tmp_dir = temp_workspace_dir(version_code)?;
    fs::create_dir_all(&tmp_dir)
        .with_context(|| format!("failed to create temp directory {}", tmp_dir.display()))?;

    let apk_path = tmp_dir.join(&apk_name);
    let mut response = client
        .get(&apk_url)
        .send()
        .with_context(|| format!("failed to download APK from {}", apk_url))?
        .error_for_status()
        .with_context(|| format!("APK download request failed for {}", apk_url))?;

    println!("[termux-setmeup] downloading {}", apk_url);
    let mut out = File::create(&apk_path)
        .with_context(|| format!("failed to create file {}", apk_path.display()))?;
    copy(&mut response, &mut out)
        .with_context(|| format!("failed to write file {}", apk_path.display()))?;

    println!(
        "[termux-setmeup] installing {} via adb",
        apk_path.display()
    );
    runner::run_owned(
        "adb",
        &[
            "install".to_string(),
            "-r".to_string(),
            apk_path.display().to_string(),
        ],
    )?;

    println!(
        "[termux-setmeup] Termux installed from F-Droid (versionCode={})",
        version_code
    );
    Ok(())
}

/// Installs embedded extra packages using apt.
pub fn install_extra_packages(remote: &str, port: u16) -> Result<()> {
    let packages = parse_embedded_packages(EMBEDDED_EXTRA_PACKAGES);
    if packages.is_empty() {
        println!("[termux-setmeup] no embedded extra packages configured");
        return Ok(());
    }

    for package in &packages {
        if !is_safe_package_name(package) {
            return Err(anyhow::anyhow!(
                "invalid package name in embedded list: {}",
                package
            ));
        }
    }

    let mut remote_command = String::from("apt install -y --no-install-recommends");
    for package in &packages {
        remote_command.push(' ');
        remote_command.push_str(package);
    }

    let args = vec![
        "-p".to_string(),
        port.to_string(),
        remote.to_string(),
        remote_command,
    ];

    runner::run_owned("ssh", &args)
}

/// Installs embedded apt tweak config into Termux apt.conf.d on the remote host.
pub fn install_apt_tweaks(remote: &str, port: u16) -> Result<()> {
    let remote_workspace = "$HOME/termux-setmeup";
    let remote_workspace_file = format!("{}/my-apt.conf", remote_workspace);
    let remote_target = "$PREFIX/etc/apt/apt.conf.d/my-apt.conf";

    // Ensure upload staging directory exists remotely.
    runner::run_owned(
        "ssh",
        &[
            "-p".to_string(),
            port.to_string(),
            remote.to_string(),
            format!("mkdir -p \"{}\"", remote_workspace),
        ],
    )?;

    // Upload embedded config content using plain ssh stdin streaming.
    runner::run_with_stdin(
        "ssh",
        &[
            "-p".to_string(),
            port.to_string(),
            remote.to_string(),
            format!("cat > \"{}\"", remote_workspace_file),
        ],
        EMBEDDED_APT_TWEAKS.as_bytes(),
    )?;

    // Copy into Termux apt.conf.d location.
    runner::run_owned(
        "ssh",
        &[
            "-p".to_string(),
            port.to_string(),
            remote.to_string(),
            format!(
                "mkdir -p \"$PREFIX/etc/apt/apt.conf.d\" && cp \"{}\" \"{}\"",
                remote_workspace_file, remote_target
            ),
        ],
    )?;

    if runner::is_dry_run() {
        println!(
            "[termux-setmeup] dry-run: would install apt tweaks at {} on {}",
            remote_target, remote
        );
    } else {
        println!(
            "[termux-setmeup] installed apt tweaks at {} on {}",
            remote_target, remote
        );
    }

    Ok(())
}

/// Creates a unique temporary workspace directory path for APK downloads.
fn temp_workspace_dir(version_code: u64) -> Result<std::path::PathBuf> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock before UNIX_EPOCH")?
        .as_millis();
    Ok(std::env::temp_dir().join(format!(
        "termux-setmeup-{}-{}",
        version_code, millis
    )))
}

/// Parses package names from embedded text lines, ignoring blanks and comments.
fn parse_embedded_packages(raw: &str) -> Vec<String> {
    raw.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| !line.starts_with('#'))
        .map(ToOwned::to_owned)
        .collect()
}

/// Validates package names to avoid unsafe shell fragments in remote command strings.
fn is_safe_package_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '+' | '-'))
}

#[cfg(test)]
mod tests {
    use super::parse_embedded_packages;

    #[test]
    fn parse_embedded_packages_ignores_blank_and_comment_lines() {
        let raw = "\
# comment
nano

mc
  # spaced comment
htop
";
        let packages = parse_embedded_packages(raw);
        assert_eq!(packages, vec!["nano", "mc", "htop"]);
    }

    #[test]
    fn is_safe_package_name_allows_common_apt_names() {
        assert!(super::is_safe_package_name("python3"));
        assert!(super::is_safe_package_name("libssl3"));
        assert!(super::is_safe_package_name("pkg-config"));
        assert!(super::is_safe_package_name("libstdc++"));
        assert!(super::is_safe_package_name("my.pkg"));
    }

    #[test]
    fn is_safe_package_name_rejects_shell_fragments() {
        assert!(!super::is_safe_package_name("foo;rm"));
        assert!(!super::is_safe_package_name("foo bar"));
        assert!(!super::is_safe_package_name("`cmd`"));
        assert!(!super::is_safe_package_name("$(cmd)"));
    }
}
