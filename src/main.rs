//! CLI entrypoint for `termux-setmeup`.
//!
//! This binary is intentionally options-only (no subcommands). The current
//! action surface is `--install-termux`.

mod actions;
mod runner;

use anyhow::Result;
use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "termux-setmeup")]
#[command(version, about = "Termux setup CLI")]
/// Command-line options accepted by the binary.
struct Cli {
    /// Print commands without executing them.
    #[arg(long, default_value_t = false)]
    dry_run: bool,

    /// Execute adb-install-termux action.
    #[arg(long, default_value_t = false)]
    install_termux: bool,

    /// Install embedded extra packages via apt.
    #[arg(long, default_value_t = false)]
    install_extra_packages: bool,

    /// Install embedded apt tweaks into Termux apt.conf.d on remote host.
    #[arg(long, default_value_t = false)]
    install_apt_tweaks: bool,

    /// Remote target in user@host[:port] format (required for remote actions).
    #[arg(long)]
    remote: Option<String>,
}

/// Parses CLI options and dispatches requested actions.
fn main() -> Result<()> {
    let cli = Cli::parse();
    runner::set_dry_run(cli.dry_run);

    let mut did_run = false;
    if cli.install_termux {
        actions::adb_install_termux()?;
        did_run = true;
    }

    if cli.install_extra_packages {
        let remote_with_optional_port = cli
            .remote
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("--remote is required when using --install-extra-packages"))?;
        let (remote, port) = parse_remote_with_optional_port(remote_with_optional_port)?;

        actions::install_extra_packages(&remote, port)?;
        did_run = true;
    }

    if cli.install_apt_tweaks {
        let remote_with_optional_port = cli
            .remote
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("--remote is required when using --install-apt-tweaks"))?;
        let (remote, port) = parse_remote_with_optional_port(remote_with_optional_port)?;

        actions::install_apt_tweaks(&remote, port)?;
        did_run = true;
    }

    if !did_run {
        println!(
            "[termux-setmeup] no action requested (use --install-termux and/or --install-extra-packages and/or --install-apt-tweaks)"
        );
    }

    Ok(())
}

/// Parses `user@host[:port]` and returns `(user@host, port)`.
fn parse_remote_with_optional_port(raw: &str) -> Result<(String, u16)> {
    if !raw.contains('@') {
        return Err(anyhow::anyhow!(
            "invalid --remote value '{}': expected user@host[:port]",
            raw
        ));
    }

    if let Some((lhs, rhs)) = raw.rsplit_once(':') {
        if rhs.chars().all(|c| c.is_ascii_digit()) {
            let port = rhs.parse::<u16>().map_err(|_| {
                anyhow::anyhow!(
                    "invalid --remote value '{}': port out of range in user@host:port",
                    raw
                )
            })?;
            if lhs.is_empty() {
                return Err(anyhow::anyhow!(
                    "invalid --remote value '{}': missing host before :port",
                    raw
                ));
            }
            return Ok((lhs.to_string(), port));
        }
    }

    Ok((raw.to_string(), 22))
}

#[cfg(test)]
mod tests {
    use super::parse_remote_with_optional_port;

    #[test]
    fn parse_remote_with_port() {
        let (remote, port) = parse_remote_with_optional_port("user@host:2222").unwrap();
        assert_eq!(remote, "user@host");
        assert_eq!(port, 2222);
    }

    #[test]
    fn parse_remote_without_port_defaults_to_22() {
        let (remote, port) = parse_remote_with_optional_port("user@host").unwrap();
        assert_eq!(remote, "user@host");
        assert_eq!(port, 22);
    }

    #[test]
    fn parse_remote_rejects_missing_user_at_host() {
        assert!(parse_remote_with_optional_port("host:22").is_err());
    }
}
