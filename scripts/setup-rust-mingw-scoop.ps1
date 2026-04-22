$ErrorActionPreference = "Stop"

Write-Host "==> Removing existing Rust Scoop packages (ignore errors if not installed)..."
try { scoop uninstall --purge rust } catch {}
try { scoop uninstall --purge rust-gnu } catch {}

Write-Host "==> Installing GNU Rust toolchain via Scoop..."
scoop install rustup-gnu gcc
scoop reset rustup-gnu

Write-Host "==> Configuring rustup GNU toolchain..."
rustup toolchain install stable-x86_64-pc-windows-gnu
rustup default stable-x86_64-pc-windows-gnu
rustup component add rustfmt clippy

Write-Host "==> Verifying toolchain..."
where.exe cargo
rustc -vV
cargo -vV
gcc --version
cargo fmt --version
cargo clippy --version

Write-Host "Done."
