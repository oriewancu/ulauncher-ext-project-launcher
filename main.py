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
        
        # Expand base_dir immediately
        base_dir = extension.expand_path(extension.preferences['base_dir'])

        if not os.path.exists(base_dir):
            return RenderResultListAction([
                ExtensionResultItem(
                    icon='images/icon.png', 
                    name="Error: Path not found", 
                    description=f"Path '{base_dir}' does not exist. Check Preferences.")
            ])

        projects = [d for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]
        filtered = [p for p in projects if query in p.lower()][:8]

        for project in filtered:
            items.append(ExtensionResultItem(
                icon='images/icon.png',
                name=project,
                description=f"Manage project {project}",
                on_enter=ExtensionCustomAction({"action": "show_menu", "project": project}, keep_app_open=True)
            ))

        return RenderResultListAction(items)

class ItemEnterEventListener(EventListener):
    def on_event(self, event, extension):
        data = event.get_data()
        action = data.get("action")
        project = data.get("project")
        
        # Expand all preference paths
        base_dir = extension.expand_path(extension.preferences['base_dir'])
        idea_bin = extension.expand_path(extension.preferences['idea_bin'])
        git_tool = extension.preferences['git_tool']
        terminal = extension.expand_path(extension.preferences['terminal_emulator'])
        
        # Ensure path is fully expanded
        path = data.get("path") or (os.path.join(base_dir, project) if project else "")

        if action == "show_menu":
            return RenderResultListAction([
                ExtensionResultItem(icon='images/git-icon.png', name="Git Tool", on_enter=ExtensionCustomAction({"action": "run_git", "path": path})),
                ExtensionResultItem(icon='images/intellij-idea-ide-icon.png', name="Open in IntelliJ IDEA", on_enter=ExtensionCustomAction({"action": "run_idea", "path": path})),
                ExtensionResultItem(icon='images/visual-studio-code-icon.png', name="Open in VS Code", on_enter=ExtensionCustomAction({"action": "run_code", "path": path})),
                ExtensionResultItem(icon='images/terminal-icon.png', name="Open in Terminal", on_enter=ExtensionCustomAction({"action": "run_terminal", "path": path})),
                ExtensionResultItem(icon='images/sonar-icon.png', name="Sonar 8.9 (LTS)", on_enter=ExtensionCustomAction({"action": "run_sonar", "path": path, "ver": "8.9"})),
                ExtensionResultItem(icon='images/sonar-icon.png', name="Sonar Latest", on_enter=ExtensionCustomAction({"action": "run_sonar", "path": path, "ver": "latest"}))
            ])

        if action == "run_idea":
            subprocess.Popen([idea_bin, path], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        elif action == "run_code":
            subprocess.Popen(["code", path], start_new_session=True)
        
        elif action == "run_terminal":
            cmd = f"cd '{path}' ; exec bash"
            subprocess.Popen([terminal, "--", "bash", "-c", cmd])

        elif action == "run_git":
            # Note: Wrap path and git_tool in quotes to handle spaces
            cmd = f"cd '{path}' && source '{git_tool}'; exec bash"
            subprocess.Popen([terminal, "--", "bash", "-c", cmd])

        elif action == "run_sonar":
            if data.get("ver") == "8.9":
                url = extension.preferences['sonar_89_url']
                token = extension.preferences['sonar_89_token']
                login_flag = "-Dsonar.login="
            else:
                url = extension.preferences['sonar_latest_url']
                token = extension.preferences['sonar_latest_token']
                login_flag = "-Dsonar.token="
            
            mvn_cmd = (
                f"mvn clean verify org.sonarsource.scanner.maven:sonar-maven-plugin:sonar "
                f"-Dsonar.host.url={url} "
                f"{login_flag}{token}"
            )
            
            subprocess.Popen([
                terminal, 
                "--working-directory", path, 
                "--", "bash", "-c", 
                f"echo 'Running SonarQube Scan...'; {mvn_cmd}; echo -e '\\nScan finished!'; read -p 'Press Enter to close...'"
            ])

        return HideWindowAction()

if __name__ == '__main__':
    ProjectLauncher().run()