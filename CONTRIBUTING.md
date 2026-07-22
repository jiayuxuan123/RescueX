# Contributing to RescueX

## Development Environment

RescueX is a Magisk/KernelSU/APatch module. You can develop it on any Android device with root access or in an emulator.

### Prerequisites

- Android device with root access
- Magisk (v27+), KernelSU, or APatch installed
- Basic knowledge of shell scripting and Android module structure

### File Structure

```
RescueX/
├── META-INF/com/google/android/     # Magisk installer
├── common.sh                         # Shared function library
├── post-fs-data.sh                   # Early boot rescue logic
├── service.sh                        # Late boot success handling
├── customize.sh                      # Install-time setup
├── uninstall.sh                      # Clean uninstall
├── action.sh                         # CLI / WebUI entry point
├── watchdog.sh                       # Boot timeout monitor
├── module.prop                       # Module metadata
├── webroot/                          # WebUI frontend
│   ├── index.html
│   ├── script.js
│   └── style.css
└── state/                            # Runtime state (auto-created)
```

### Building

No build step required. The module directory itself is the importable package:

```bash
zip -r RescueX-vX.Y.Z-import.zip \
  META-INF module.prop customize.sh \
  post-fs-data.sh service.sh uninstall.sh \
  action.sh common.sh watchdog.sh integrity.sh webroot
```

### Testing

1. Push the zip to `/sdcard/`
2. Install via Magisk/KernelSU manager
3. Reboot
4. Open WebUI to verify all panels load correctly

### Code Style

- Shell scripts: POSIX-compatible, avoid bashisms
- JavaScript: ES6+, no external dependencies
- HTML/CSS: Material Design 3 style, responsive layout
- All scripts should pass `sh -n` syntax check
- JavaScript should pass `node --check`

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Verify with syntax checks
5. Test on device if possible
6. Submit a pull request with a clear description

## Reporting Issues

When reporting bugs, please include:

- Device model and Android version
- Root solution (Magisk/KernelSU/APatch) and version
- RescueX version
- Relevant log output from `boot_status`, `rescue.log`, and `boot_history`
- Steps to reproduce
