import { spawnSync } from "node:child_process";
import { join } from "node:path";

const scripts = import.meta.dirname;
const windows = process.platform === "win32";
const [command, args] = windows
  ? [
      "powershell",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", join(scripts, "install.ps1")],
    ]
  : ["bash", [join(scripts, "install.sh")]];

process.exit(spawnSync(command, args, { stdio: "inherit" }).status ?? 1);
