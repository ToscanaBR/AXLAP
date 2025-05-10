from elasticsearch import Elasticsearch

class AXLAPElasticsearchClient:
    def __init__(self, config):
        self.host = config.get('elasticsearch', 'host', fallback='127.0.0.1')
        self.port = config.getint('elasticsearch', 'port', fallback=9200)
        self.scheme = config.get('elasticsearch', 'scheme', fallback='http')
        try:
            self.es = Elasticsearch([{'host': self.host, 'port': self.port, 'scheme': self.scheme}])
            if not self.es.ping():
                raise ConnectionError(f"Failed to connect to Elasticsearch at {self.scheme}://{self.host}:{self.port}")
        except Exception as e:
            # Log this or raise it to be handled by TUI
            # For TUI, it's better to let it be handled and shown in status.
            self.es = None 
            print(f"Error connecting to ES: {e}") # For console log during TUI startup
            # raise ConnectionError(f"ES Init Failed: {e}") # Let TUI handle this


    def search(self, index_pattern, query_body, size=10, sort=None):
        if not self.es: return {"hits": {"hits": []}} # Return empty if no connection
        # Default sort if none provided
        if sort is None:
            sort = [{"@timestamp": "desc"}] if "@timestamp" not in query_body.get("sort", [{}])[0] else query_body.get("sort")

        search_params = {
            "index": index_pattern,
            "body": query_body,
            "size": size,
            "sort": sort,
            "ignore_unavailable": True, # Don't fail if some daily indices are missing
            "allow_no_indices": True
        }
        return self.es.search(**search_params)

    def count(self, index_pattern, query_body=None):
        if not self.es: return {"count": 0}
        if query_body is None:
            query_body = {"query": {"match_all": {}}}
        
        count_params = {
            "index": index_pattern,
            "body": query_body,
            "ignore_unavailable": True,
            "allow_no_indices": True
        }
        return self.es.count(**count_params)

    def get_document(self, index, doc_id, ignore_errors=True):
        if not self.es:
            return None
        try:
            return self.es.get(index=index, id=doc_id)
        except Exception as e:  # Catch all exceptions for now, including NotFoundError
            if not ignore_errors:
                raise  # Re-raise the exception if we're not ignoring errors
            else:
                print(f"Error getting document {doc_id} from index {index}: {e}")
            return None
