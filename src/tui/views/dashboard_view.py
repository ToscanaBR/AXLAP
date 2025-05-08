import curses
import time
from . import BaseView # Use the BaseView defined in __init__.py or base_view.py

class DashboardView(BaseView):
        def __init__(self, stdscr, config, es_client):
            super().__init__(stdscr, config, es_client) # Pass es_client to BaseView
            self.es_client = es_client # Or self.clients[0]
            self.force_refresh_data() # Initial data load

        def fetch_data(self):
            # Fetch summary data from Elasticsearch: Suricata alerts, ML alerts, Zeek log counts
            data = {"alerts": [], "ml_alerts": [], "log_counts": {}, "error": None}
            try:
                # Fetch Suricata alerts (last 1 hour, top 5)
                suricata_alerts_query = {
                    "query": {"bool": {"must": [{"match": {"event.kind": "suricata_alert"}}]}}, # updated field
                    "size": 5,
                    "sort": [{"@timestamp": "desc"}]
                }
                res_suricata = self.es_client.search("axlap-suricata-*", suricata_alerts_query)
                data["alerts"] = [
                    f"{hit['_source'].get('@timestamp')} - {hit['_source'].get('alert',{}).get('signature','N/A')} (Severity: {hit['_source'].get('alert',{}).get('severity','N/A')})"
                    for hit in res_suricata.get('hits', {}).get('hits', [])
                ]

                # Fetch ML alerts (last 1 hour, top 5)
                ml_alerts_query = {
                    "query": {"match_all": {}},
                    "size": 5,
                    "sort": [{"timestamp": "desc"}] # Assuming 'timestamp' field in ML alerts
                }
                res_ml = self.es_client.search(f"{self.config.get('elasticsearch', 'ml_alert_index_pattern', fallback='axlap-ml-alerts-*')}", ml_alerts_query)
                data["ml_alerts"] = [
                    f"{hit['_source'].get('timestamp')} - {hit['_source'].get('description','N/A')} (Score: {hit['_source'].get('anomaly_score',0.0):.2f})"
                    for hit in res_ml.get('hits', {}).get('hits', [])
                ]

                # Fetch Zeek log counts (conn, http, dns for today)
                log_types = ["conn", "http", "dns", "axlap_http_detailed", "axlap_conn_stats"] # Include custom Zeek logs
                for log_type in log_types:
                    # Assuming Zeek logs go into axlap-zeek-* and have a field like 'event.module' or part of filename in _index
                    # For simplicity, let's assume they are distinguishable by index name or a field.
                    # If all Zeek logs are in 'axlap-zeek-*', we need a field like 'log_type' or 'event.dataset'
                    # Example: search for docs where _index contains the log_type (e.g. axlap-zeek-conn-*)
                    # This depends heavily on Filebeat/ES indexing setup.
                    # A simple count on the main axlap-zeek-* index:
                    # count_query = {"query": {"match": {"event.dataset": f"zeek.{log_type}"}}} # if using ECS event.dataset
                    # For now, a placeholder:
                    # count_res = self.es_client.count(f"axlap-zeek-{log_type}-*", {"query":{"match_all":{}}})
                    # More general: count all in axlap-zeek-*
                    if log_type == "conn": # just as example
                        count_res = self.es_client.count("axlap-zeek-*", {"query":{"exists":{"field":"uid"}}}) # conn logs have uid
                        data["log_counts"][log_type] = count_res.get('count', 0)
                    else: # Placeholder for other log types
                        data["log_counts"][log_type] = "N/A (implement specific count)"


            except Exception as e:
                data["error"] = str(e)
            
            return data

        def _draw_content(self):
            # self.view_win is the sub-window for this view's content
            h, w = self.view_win.getmaxyx()

            if self.data.get("error"):
                self.view_win.attron(curses.color_pair(3))
                self.view_win.addstr(1, 1, f"Error fetching dashboard data: {self.data['error'][:w-3]}")
                self.view_win.attroff(curses.color_pair(3))
                return

            y_offset = 1

            # Suricata Alerts
            self.view_win.attron(curses.color_pair(5) | curses.A_BOLD)
            self._safe_addstr(y_offset, 1, "Recent Suricata Alerts:")
            self.view_win.attroff(curses.color_pair(5) | curses.A_BOLD)
            y_offset += 1
            for alert in self.data["alerts"]:
                if y_offset >= h -1: break
                self._safe_addstr(y_offset, 3, alert)
                y_offset += 1
            if not self.data["alerts"]:
                self._safe_addstr(y_offset, 3, "No recent Suricata alerts.", curses.color_pair(4))
                y_offset +=1
            
            y_offset += 1 # Spacer

            # ML Alerts
            self.view_win.attron(curses.color_pair(5) | curses.A_BOLD)
            self._safe_addstr(y_offset, 1, "Recent ML Behavioral Flags:")
            self.view_win.attroff(curses.color_pair(5) | curses.A_BOLD)
            y_offset += 1
            for alert in self.data["ml_alerts"]:
                if y_offset >= h -1: break
                self._safe_addstr(y_offset, 3, alert)
                y_offset += 1
            if not self.data["ml_alerts"]:
                self._safe_addstr(y_offset, 3, "No recent ML alerts.", curses.color_pair(4))
                y_offset +=1

            y_offset += 1 # Spacer

            # Log Counts
            self.view_win.attron(curses.color_pair(5) | curses.A_BOLD)
            self._safe_addstr(y_offset, 1, "Zeek Log Counts (Today/Approx):")
            self.view_win.attroff(curses.color_pair(5) | curses.A_BOLD)
            y_offset += 1
            for log_type, count in self.data["log_counts"].items():
                if y_offset >= h -1: break
                self._safe_addstr(y_offset, 3, f"{log_type.capitalize()}: {count}")
                y_offset += 1
            
        def handle_input(self, key):
            # Dashboard might not have much specific input, maybe navigation if lists are long
            pass
