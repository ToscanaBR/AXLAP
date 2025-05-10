import requests
import json

class OpenCTIClient:
    def __init__(self, config):
        self.config = config
        self.base_url = config.get("OPENCTI_URL", "http://localhost:8080")  # Default URL
        self.api_token = config.get("OPENCTI_TOKEN")
        if not self.api_token:
            raise ValueError("OPENCTI_TOKEN must be provided in the configuration.")
        self.headers = {
            "Authorization": f"Bearer {self.api_token}",
            "Content-Type": "application/json",
        }

    def _execute_graphql_query(self, query, variables=None):
        """Executes a GraphQL query against the OpenCTI API."""
        url = f"{self.base_url}/graphql"
        payload = {"query": query}
        if variables:
            payload["variables"] = variables

        try:
            response = requests.post(url, headers=self.headers, data=json.dumps(payload))
            response.raise_for_status()  # Raise HTTPError for bad responses
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"OpenCTI GraphQL query error: {e}")
            return None

    def get_correlations(self, source_id, target_types=None, relationship_type="related-to"):
        """
        Retrieves correlations (relationships) for a given source entity.

        Args:
            source_id (str): The ID of the source entity in OpenCTI.
            target_types (list, optional): List of target entity types to filter by. Defaults to None (all types).
            relationship_type (str, optional): The type of relationship to retrieve. Defaults to "related-to".

        Returns:
            list: A list of correlation dictionaries, or None if an error occurs.  Each dictionary contains 'source', 'target', and 'relationship' information.
        """
        query = """
            query Relationships($fromId: StixId!, $relationship_type: String!, $targetTypes: [String]) {
              stixCoreRelationships(
                first: 100, # Adjust as needed, use pagination for more results
                fromId: $fromId,
                relationship_type: $relationship_type,
                targetTypes: $targetTypes
              ) {
                edges {
                  node {
                    id
                    from { name }
                    to { name }
                    relationship_type
                  }
                }
              }
            }
        """
        variables = {"fromId": source_id, "relationship_type": relationship_type, "targetTypes": target_types}
        result = self._execute_graphql_query(query, variables)
        if result and "data" in result and "stixCoreRelationships" in result["data"]:
            relationships = result["data"]["stixCoreRelationships"]["edges"]
            return [{"source": rel["node"]["from"]["name"], "target": rel["node"]["to"]["name"], "relationship": rel["node"]["relationship_type"]} for rel in relationships]
        else:
            return None
