import curses
from datetime import datetime, timedelta

class QueryView:
    def __init__(self, stdscr, config, arkime_client, es_client):
        self.stdscr = stdscr
        self.config = config
        # ...existing initialization if any...
        self.arkime_client = arkime_client
        self.es_client = es_client
        self.query = ""
        self.results = []
        self.selected_result = 0
        self.message = ""
        self.current_page = 0
        self.results_per_page = 10

    def draw(self, height, width):
        # ...existing code...
        self.stdscr.clear()
        self.stdscr.addstr(1, 1, "Query View (stub)")
        self.stdscr.addstr(1, 1, "Arkime Query")
        self.stdscr.addstr(2, 1, f"Query: {self.query}")
        self.stdscr.addstr(3, 1, "-" * (width - 2))

        if self.message:
            self.stdscr.addstr(4, 1, self.message)

        if self.results:
            start_index = self.current_page * self.results_per_page
            end_index = min(start_index + self.results_per_page, len(self.results))
            y = 6
            for i in range(start_index, end_index):
                result = self.results[i]
                display_str = f"[{i+1}] {result.get('srcip', 'N/A')} -> {result.get('dstip', 'N/A')}:{result.get('dstport', 'N/A')}"
                if i == start_index + self.selected_result:
                    self.stdscr.addstr(y, 3, display_str, curses.A_REVERSE)
                else:
                    self.stdscr.addstr(y, 3, display_str)
                y += 1

            if len(self.results) > self.results_per_page:
                total_pages = (len(self.results) + self.results_per_page - 1) // self.results_per_page
                self.stdscr.addstr(height - 2, 1, f"Page {self.current_page + 1}/{total_pages}.  Use PgUp/PgDn to navigate pages.")
            else:
                self.stdscr.addstr(height - 2, 1, "Use Up/Down arrows to select, Enter to view details (not implemented).")
        else:
            self.stdscr.addstr(6, 1, "No results. Enter a query and press Enter to search.")

        self.stdscr.refresh()

    def handle_input(self, key):
        # ...existing code...
        pass
        if key == curses.KEY_ENTER or key == 10:
            self.execute_query()
        elif key == curses.KEY_UP:
            self.selected_result = max(0, self.selected_result - 1)
        elif key == curses.KEY_DOWN:
            self.selected_result = min(self.results_per_page -1, self.selected_result + 1) # Corrected this line
        elif key == curses.KEY_PPAGE:  # Page Up
            self.current_page = max(0, self.current_page - 1)
            self.selected_result = 0
        elif key == curses.KEY_NPAGE:  # Page Down
            total_pages = (len(self.results) + self.results_per_page - 1) // self.results_per_page
            self.current_page = min(total_pages - 1, self.current_page + 1)
            self.selected_result = 0
        elif key == curses.KEY_BACKSPACE or key == 127:  # Backspace
            self.query = self.query[:-1]
        else:
            try:
                self.query += chr(key)
            except ValueError:
                pass  # Ignore non-character keys

    def update(self):
        # ...existing code...
        pass
        # Placeholder for any dynamic updates (e.g., auto-refresh)
        pass

    def execute_query(self):
        self.message = "Searching..."
        self.draw(self.stdscr.getmaxyx()[0], self.stdscr.getmaxyx()[1]) # Update screen with message
        self.results = []
        self.current_page = 0
        self.selected_result = 0

        try:
            if not self.query:
                self.message = "Please enter a query."
                return

            # Example: Search for sessions in the last 24 hours if no time range in query
            if " " not in self.query and not any(op in self.query for op in ["<", ">", ":", "firstPacket", "lastPacket"]):
                now = datetime.utcnow()
                start_time = (now - timedelta(days=1)).isoformat() + "Z"
                end_time = now.isoformat() + "Z"
                arkime_query = f"{self.query} && lastPacket>={start_time} && lastPacket<{end_time}"
            else:
                arkime_query = self.query

            self.results = self.arkime_client.search_sessions(arkime_query)
            if self.results:
                self.message = f"Found {len(self.results)} results."
            else:
                self.message = "No results found."
        except Exception as e:
            self.message = f"Error: {e}"
            self.results = []

        self.draw(self.stdscr.getmaxyx()[0], self.stdscr.getmaxyx()[1])  # Update screen with results or erro