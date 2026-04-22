/**
 * npm postinstall bootstrapper for termux-setmeup.
 *
 * On supported Termux hosts (android/linux arm64), this downloads the
 * release `.deb` from GitHub and installs it via `dpkg`.
 */
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const https = require("node:https");
const { execSync } = require("node:child_process");

/**
 * Print installer log line.
 * @param {string} msg
 */
function log(msg) {
  console.log(`[termux-setmeup npm] ${msg}`);
}

/**
 * Detect whether current environment looks like Termux.
 * @returns {boolean}
 */
function isTermux() {
  const prefix = process.env.PREFIX || "";
  if (prefix.includes("/data/data/com.termux/files/usr")) return true;
  if (process.env.npm_config_prefix === "/data/data/com.termux/files/usr") return true;
  if (fs.existsSync("/data/data/com.termux/files/usr/bin/pkg")) return true;
  return false;
}

/**
 * Exit successfully on unsupported platforms so npm install itself does not fail.
 */
function failUnsupported() {
  log("No prebuilt binaries available for your platform.");
  log(
    `Detected: platform=${process.platform} arch=${process.arch} PREFIX=${process.env.PREFIX || "<unset>"}`
  );
  log("Supported: Termux on android/arm64 or linux/arm64.");
  process.exit(0);
}

/**
 * Download a file over HTTPS, following redirects.
 * @param {string} url
 * @param {string} destination
 * @param {number} redirectsLeft
 * @returns {Promise<void>}
 */
function download(url, destination, redirectsLeft = 5) {
  return new Promise((resolve, reject) => {
    const req = https.get(
      url,
      { headers: { "user-agent": "termux-setmeup-npm-installer" } },
      (res) => {
        const code = res.statusCode || 0;

        if (code >= 300 && code < 400 && res.headers.location) {
          if (redirectsLeft <= 0) {
            reject(new Error(`Too many redirects for ${url}`));
            return;
          }
          // Drain redirect response and follow Location without touching destination file.
          res.resume();
          const nextUrl = new URL(res.headers.location, url).toString();
          download(nextUrl, destination, redirectsLeft - 1)
            .then(resolve)
            .catch(reject);
          return;
        }

        if (code !== 200) {
          reject(new Error(`Download failed (${code}) for ${url}`));
          return;
        }

        const file = fs.createWriteStream(destination);
        res.pipe(file);
        file.on("finish", () => file.close(resolve));
        file.on("error", (err) => {
          file.close(() => fs.unlink(destination, () => {}));
          reject(err);
        });
      }
    );
    req.on("error", reject);
  });
}

/**
 * Main installer flow:
 * - validate supported platform
 * - download release deb
 * - install with dpkg and repair deps if needed
 */
async function main() {
  const supportedPlatform =
    process.platform === "linux" || process.platform === "android";
  if (!supportedPlatform || process.arch !== "arm64" || !isTermux()) {
    failUnsupported();
    return;
  }

  const version = require("../package.json").version;
  const debName = `termux-setmeup_${version}_aarch64.deb`;
  const debUrl = `https://github.com/your-user/termux-setmeup/releases/download/v${version}/${debName}`;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "termux-setmeup-npm-"));
  const debPath = path.join(tmpDir, debName);

  log(`Downloading ${debName}...`);
  await download(debUrl, debPath);

  if (!fs.existsSync(debPath)) {
    throw new Error(`Downloaded file not found: ${debPath}`);
  }

  log("Installing local .deb with dpkg...");
  try {
    execSync(`dpkg -i "${debPath}"`, {
      stdio: "inherit",
    });
  } catch (_dpkgErr) {
    log("dpkg reported missing deps; running apt -f install...");
    execSync("apt -f install -y", { stdio: "inherit" });
  }

  log("Done. Run: termux-setmeup");
}

main().catch((err) => {
  console.error(`[termux-setmeup npm] ${err.message}`);
  process.exit(1);
});

