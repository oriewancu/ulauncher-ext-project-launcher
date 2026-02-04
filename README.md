# 🚀 Personal Project Launcher (Ulauncher Extension)

A specialized Ulauncher extension for developers to accelerate project management and launch projects directly from your desktop.

## ✨ Key Features
- **Project Discovery**: Instantly search for project folders within a configurable base directory.
- **Dual IDE Support**: Open projects directly in IntelliJ IDEA or Visual Studio Code.
- **SonarQube Integration**: Run Code Coverage scans for both 8.9 (LTS) and Latest versions with a single click.
- **Git Tooling**: Quick access to your custom Git management scripts.
- **Flexible Path Support**: Supports `~/` and `$HOME` syntax for project directories and executables.

## 📖 Usage
1. Trigger Ulauncher and type the keyword (default: `p`).
2. Type the name of your folder project.
3. Select the desired action:
   - **Open in IntelliJ IDEA**
   - **Open in VS Code**
   - **Run Sonar Scan (8.9 / Latest)**
   - **Open Git Tool**

## 🛠 Installation

### Via Ulauncher (Easiest)
1. Open Ulauncher Preferences > Extensions > Add Extension.
2. Paste the repository URL: `https://github.com/oriewancu/ulauncher-ext-project-launcher`

### From Source (Development)
1. Navigate to the extensions folder:
   `cd ~/.local/share/ulauncher/extensions/`
2. Clone the repository:
   `git clone https://github.com/oriewancu/ulauncher-ext-project-launcher`
3. Restart Ulauncher.

---

## ⚙️ Configuration
Access **Preferences > Extensions** in Ulauncher to set up:
- **Base Projects Directory**: Your project root (e.g., `~/Projects/java`).
- **IntelliJ Path**: Path to your `idea` binary.
- **Sonar Settings**: Configure specific URLs and Tokens for each SonarQube version.
- **Terminal Emulator**: Terminal used for Maven processes (e.g., `gnome-terminal`).

## 🛠 Troubleshooting
- **IDE won't open**: Ensure the `idea_bin` path is correct and the file has execution permissions.
- **Sonar Scan fails**: Verify your SonarQube Server/Docker is running on the configured port.

## 📄 License
This project is licensed under the MIT License.