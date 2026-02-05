#!/usr/bin/env python3

import os
import subprocess
from ulauncher.api.client.Extension import Extension
from ulauncher.api.client.EventListener import EventListener
from ulauncher.api.shared.event import KeywordQueryEvent, ItemEnterEvent
from ulauncher.api.shared.item.ExtensionResultItem import ExtensionResultItem
from ulauncher.api.shared.action.RenderResultListAction import RenderResultListAction
from ulauncher.api.shared.action.ExtensionCustomAction import ExtensionCustomAction
from ulauncher.api.shared.action.HideWindowAction import HideWindowAction

class ProjectLauncher(Extension):
    def __init__(self):
        super(ProjectLauncher, self).__init__()
        self.subscribe(KeywordQueryEvent, KeywordQueryEventListener())
        self.subscribe(ItemEnterEvent, ItemEnterEventListener())

    def expand_path(self, path):
        """Helper to handle ~ and $VARs"""
        if not path:
            return ""
        return os.path.expanduser(os.path.expandvars(path))

class KeywordQueryEventListener(EventListener):
    def on_event(self, event, extension):
        items = []
        query = (event.get_argument() or "").lower()

        raw_base_dirs = extension.preferences.get('base_dir', "").split(',')

        active_dirs = []
        for path_str in raw_base_dirs:
            path_str = path_str.strip()
            if not path_str or path_str.startswith('!'):
                continue

            expanded = extension.expand_path(path_str)
            if os.path.exists(expanded):
                active_dirs.append(expanded)

        if not active_dirs:
            return RenderResultListAction([
                ExtensionResultItem(icon='images/icon.png', name="No Active Paths", description="Check your 'base_dir' configuration.")
            ])

        all_projects = []
        for base_dir in active_dirs:
            try:
                for d in os.listdir(base_dir):
                    full_path = os.path.join(base_dir, d)
                    if os.path.isdir(full_path):
                        all_projects.append({
                            "name": d,
                            "path": full_path,
                            "parent": base_dir
                        })
            except Exception:
                continue

        filtered = [p for p in all_projects if query in p['name'].lower()][:10]

        for project in filtered:
            items.append(ExtensionResultItem(
                icon='images/icon.png',
                name=project['name'],
                description=f"Path: {project['path']}",
                on_enter=ExtensionCustomAction({
                    "action": "show_menu",
                    "project": project['name'],
                    "path": project['path']
                }, keep_app_open=True)
            ))

        return RenderResultListAction(items)

class ItemEnterEventListener(EventListener):
    def run_terminal_command(self, terminal, path, command=None):
        """Helper terminal emulator"""
        # 1. Konsole (KDE)
        if "konsole" in terminal:
            args = [terminal, "--workdir", path]
            if command:
                args += ["-e", "bash", "-ic", command]
            else:
                args += ["-e", "bash"]
            subprocess.Popen(args)

        # 2. XFCE4 Terminal
        elif "xfce4-terminal" in terminal:
            args = [terminal, "--working-directory", path]
            if command:
                args += ["-e", f"bash -ic \"{command}\""]
            else:
                args += ["-e", "bash"]
            subprocess.Popen(args)

        # 3. Terminator
        elif "terminator" in terminal:
            args = [terminal, "--working-directory", path]
            if command:
                args += ["-x", "bash", "-ic", command]
            else:
                args += ["-x", "bash"]
            subprocess.Popen(args)

        # 4. GNOME Terminal / Default
        else:
            args = [terminal, "--working-directory", path, "--"]
            if command:
                args += ["bash", "-ic", command]
            else:
                args += ["bash"]
            subprocess.Popen(args)

    def on_event(self, event, extension):
        data = event.get_data()
        action = data.get("action")
        path = data.get("path")
        
        idea_bin = extension.expand_path(extension.preferences.get('idea_bin', ''))
        git_tool = extension.expand_path(extension.preferences.get('git_tool', ''))
        terminal = extension.preferences.get('terminal_emulator', 'gnome-terminal')

        if action == "show_menu":
            sonar_ver = extension.preferences.get('sonar_version', 'sonar_89')
            sonar_label = "SonarQube 8.9 (LTS)" if sonar_ver == "sonar_89" else "SonarQube Latest"

            return RenderResultListAction([
                ExtensionResultItem(icon='images/git-icon.png', name="Git Tool", on_enter=ExtensionCustomAction({"action": "run_git", "path": path})),
                ExtensionResultItem(icon='images/intellij-idea-ide-icon.png', name="Open in IntelliJ IDEA", on_enter=ExtensionCustomAction({"action": "run_idea", "path": path})),
                ExtensionResultItem(icon='images/visual-studio-code-icon.png', name="Open in VS Code", on_enter=ExtensionCustomAction({"action": "run_code", "path": path})),
                ExtensionResultItem(icon='images/terminal-icon.png', name="Open in Terminal", on_enter=ExtensionCustomAction({"action": "run_terminal", "path": path})),
                ExtensionResultItem(icon='images/sonar-icon.png', name=f"Run {sonar_label}", on_enter=ExtensionCustomAction({"action": "run_sonar", "path": path}))
            ])

        elif action == "run_idea":
            subprocess.Popen(
                [idea_bin, path], 
                cwd=path, 
                start_new_session=True,
                stdout=subprocess.DEVNULL, 
                stderr=subprocess.DEVNULL
            )
        
        elif action == "run_code":
            subprocess.Popen(
                    ["code", path], 
                    cwd=path, 
                    start_new_session=True,
                    stdout=subprocess.DEVNULL, 
                    stderr=subprocess.DEVNULL
                )
        
        elif action == "run_terminal":
            self.run_terminal_command(terminal, path)

        elif action == "run_git":
            git_cmd = f"source '{git_tool}'; exec bash"
            self.run_terminal_command(terminal, path, command=git_cmd)

        elif action == "run_sonar":
            sonar_ver = extension.preferences.get('sonar_version', 'sonar_89')
            url = extension.preferences.get('sonar_url', '')
            token = extension.preferences.get('sonar_token', '')

            if sonar_ver == "sonar_89":
                login_flag = "-Dsonar.login="
                ver_label = "8.9 (LTS)"
            else:
                login_flag = "-Dsonar.token="
                ver_label = "Latest"
            
            mvn_cmd = (
                f"mvn clean verify org.sonarsource.scanner.maven:sonar-maven-plugin:sonar "
                f"-Dsonar.host.url={url} "
                f"{login_flag}{token}"
            )
            
            full_sonar_cmd = (
                f"echo 'Running SonarQube {ver_label} Scan...'; "
                f"{mvn_cmd}; "
                f"echo -e '\\nScan finished!'; "
                f"read -p 'Press Enter to close...'"
            )
            
            self.run_terminal_command(terminal, path, command=full_sonar_cmd)

        return HideWindowAction()

if __name__ == '__main__':
    ProjectLauncher().run()
