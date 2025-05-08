import curses
import time

class BaseView:
        def __init__(self, stdscr, config, *args): # args for specific clients like es_client
            self.stdscr = stdscr # This is the main screen, views should use sub-windows
            self.config = config
            self.clients = args # Tuple of clients passed
            self.last_update_time = 0
            self.refresh_interval = int(config.get('general', 'refresh_interval', fallback=5)) # seconds
            self.data = None # To store fetched data
            self.error_message = None
            self.is_loading = False

            # Create a dedicated window for the view content, leaving room for global header/footer
            # This will be properly sized by the main app loop before draw() is called.
            # For now, placeholder. Actual window passed or created in draw().
            self.view_win = None 

        def _create_view_window(self, h, w, y_offset=1):
            # h, w are height/width for the view's content area
            # y_offset is typically 1 (for global header)
            # This window will be where the view draws its content.
            self.view_win = self.stdscr.derwin(h, w, y_offset, 0)
            self.view_win.bkgd(' ', curses.color_pair(1)) # Default background for view window
            return self.view_win


        def draw(self, height, width):
            """Draws the view's content within the given height and width."""
            # `height` and `width` are for the area below global header, above global status
            if not self.view_win or self.view_win.getmaxyx()[0] != height or self.view_win.getmaxyx()[1] != width:
                 # Window needs to be (re)created if size changed or first draw
                 # stdscr.derwin(nlines, ncols, begin_y, begin_x)
                 self.view_win = self.stdscr.subwin(height, width, 1, 0) 
                 self.view_win.bkgd(' ', curses.color_pair(1))


            self.view_win.clear() # Clear previous content of the view window

            if self.is_loading:
                self.view_win.addstr(height // 2, (width - len("Loading...")) // 2, "Loading...")
            elif self.error_message:
                self.view_win.attron(curses.color_pair(3))
                self.view_win.addstr(1, 1, f"ERROR: {self.error_message[:width-3]}")
                self.view_win.attroff(curses.color_pair(3))
            elif self.data is not None:
                self._draw_content() # Implemented by subclasses
            else:
                self.view_win.addstr(1, 1, "No data to display. Try refreshing (F5) or check configuration.")
            
            self.view_win.refresh()


        def _draw_content(self):
            """Subclasses implement this to draw their specific data."""
            self.view_win.addstr(0,0, f"BaseView content for {self.__class__.__name__} (override _draw_content)")


        def handle_input(self, key):
            """Handles input specific to this view."""
            # Example: if key == curses.KEY_UP: self.scroll_up()
            pass # Implemented by subclasses

        def update(self):
            """Called periodically by the main loop for auto-refreshing views."""
            current_time = time.time()
            if (current_time - self.last_update_time > self.refresh_interval) and not self.is_loading:
                if hasattr(self, 'fetch_data') and callable(self.fetch_data):
                    self.force_refresh_data() # Calls fetch_data

        def force_refresh_data(self):
            """Manually triggers a data refresh for the view."""
            if hasattr(self, 'fetch_data') and callable(self.fetch_data):
                self.is_loading = True
                self.error_message = None
                # In a real app, fetch_data might be asynchronous or run in a thread
                # For simplicity here, it's synchronous
                try:
                    self.data = self.fetch_data()
                except Exception as e:
                    self.error_message = str(e)
                    self.data = None # Clear old data on error
                finally:
                    self.is_loading = False
                    self.last_update_time = time.time()
            else:
                # This view doesn't fetch data, or method is misnamed
                pass
        
        def _safe_addstr(self, y, x, text, attr=0):
            """Safely add string to view_win, handling boundaries."""
            h, w = self.view_win.getmaxyx()
            if y >= h or x >= w or y < 0 or x < 0:
                return
            
            max_len = w - x -1 # -1 for safety, border chars
            if max_len <=0: return

            display_text = (text[:max_len] + '..') if len(text) > max_len else text
            try:
                self.view_win.addstr(y, x, display_text, attr)
            except curses.error:
                pass # Curses error, typically writing outside window bounds
