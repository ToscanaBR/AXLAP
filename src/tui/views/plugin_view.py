import os
import curses

class PluginView:
    def __init__(self, stdscr, config):
        self.stdscr = stdscr
        self.config = config
        self.plugins = ["ExamplePlugin1", "ExamplePlugin2"]  # Placeholder: Replace with actual plugin loading
        self.selected_plugin = 0
        self.plugin_dir = os.path.join(self.config.get("AXLAP_BASE_DIR", "/opt/axlap"), "plugins") # Assuming plugins in AXLAP base dir
        self.load_plugins()

    
    def draw(self, height, width):
        self.stdscr.clear()
        self.stdscr.addstr(1, 1, "Plugin Manager")
        self.stdscr.addstr(2, 1, "-" * (width - 2))

        y = 4
        for i, plugin in enumerate(self.plugins):
            if i == self.selected_plugin:
                self.stdscr.addstr(y, 3, f"> {plugin}", curses.A_REVERSE)
            else:
                self.stdscr.addstr(y, 3, f"  {plugin}")
            y += 1

        self.stdscr.addstr(height - 2, 1, "Use arrow keys to navigate, Enter to select (currently does nothing).")
        self.stdscr.refresh()

    def handle_input(self, key):
        if self.plugins: # Only handle input if there are plugins
            if key == curses.KEY_UP:
                self.selected_plugin = max(0, self.selected_plugin - 1)
            elif key == curses.KEY_DOWN:
                self.selected_plugin = min(len(self.plugins) - 1, self.selected_plugin + 1)
            elif key == curses.KEY_ENTER or key == 10:  # 10 is Enter key
                self.activate_plugin()
            # Add more key bindings as needed (e.g., for plugin configuration)

    def update(self):
        # Check for new plugins or changes in existing ones
        self.load_plugins()

    def activate_plugin(self):
        if not self.plugins:
            return
        plugin_name = self.plugins[self.selected_plugin] # This is now the filename without .py
        try:
            # Basic example: Just print a message.  Replace with actual activation.
            self.stdscr.addstr(10, 3, f"Attempting to activate plugin: {plugin_name}")
            self.stdscr.refresh()
            # In a real implementation, you'd likely:
            # 1. Import the plugin module dynamically:
            #    plugin_module = __import__(f"axlap.plugins.{plugin_name}", fromlist=[''])
            # 2. Call an activation function within the plugin:
            #    if hasattr(plugin_module, 'activate'):
            #        plugin_module.activate(self.config, self.stdscr) # Pass config and stdscr if needed
            #    else:
            #        self.stdscr.addstr(11, 3, f"Plugin {plugin_name} has no 'activate' function.")
            # 3. Update some global state or configuration to reflect the plugin's activation.
            # For this example, we'll just print a message:
            # self.stdscr.addstr(10, 3, f"Activated plugin: {plugin_name}")
            # self.stdscr.refresh()
        except ImportError as e:
            self.stdscr.addstr(11, 3, f"Error importing plugin {plugin_name}: {e}")
        except Exception as e:
            self.stdscr.addstr(12, 3, f"Error activating plugin {plugin_name}: {e}")
        self.stdscr.refresh()

    def load_plugins(self):
        """Loads plugin names from the plugin directory."""
        if not os.path.exists(self.plugin_dir):
            self.plugins = []
            return
        self.plugins = [f[:-3] for f in os.listdir(self.plugin_dir) if f.endswith(".py") and not f.startswith("_")] # filenames without .py
        # In a more complex system, you might also:
        # - Check for a specific plugin interface or base class.
        # - Load plugin metadata (e.g., from a docstring or separate file)
        # - Handle potential errors during plugin loading.
        if not self.plugins:
            self.plugins = ["No plugins found. Place .py files in the plugins directory."]