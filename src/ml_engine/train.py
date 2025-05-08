import os
import joblib
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from elasticsearch import Elasticsearch
from datetime import datetime, timedelta

from ml_engine.features import create_feature_df, FEATURE_COLUMNS, get_features_for_prediction

    # Configuration
ES_HOST = os.getenv("ELASTICSEARCH_HOST", "axlap-elasticsearch")
ES_PORT = int(os.getenv("ELASTICSEARCH_PORT", 9200))
MODEL_PATH = os.path.join(os.path.dirname(__file__), "models/isolation_forest_conn.joblib")
SCALER_PATH = os.path.join(os.path.dirname(__file__), "models/scaler_conn.joblib")
TRAINING_DAYS = int(os.getenv("ML_TRAINING_DAYS", 7)) # Use last 7 days of data
MAX_TRAINING_SAMPLES = int(os.getenv("ML_MAX_TRAINING_SAMPLES", 100000)) # Limit memory usage

def fetch_data_from_es(es_client, days_ago=7, max_samples=100000):
        print(f"Fetching Zeek conn.log data from Elasticsearch for the last {days_ago} days...")
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days_ago)

        query = {
            "query": {
                "bool": {
                    "must": [
                        {"match": {"event.kind": "zeek_log"}}, # Assuming Filebeat adds this field
                        {"exists": {"field": "uid"}} # Ensure it's a conn log-like entry with uid
                    ],
                    "filter": [
                        {
                            "range": {
                                "@timestamp": { # Filebeat default timestamp field
                                    "gte": start_date.isoformat(),
                                    "lte": end_date.isoformat()
                                }
                            }
                        }
                    ]
                }
            },
            "_source": ["duration", "orig_bytes", "resp_bytes", "orig_pkts", "resp_pkts", "proto", "service", "uid", "@timestamp"], # Request specific fields
            "size": max_samples, # Limit number of samples
            "sort": [{"@timestamp": "desc"}] # Get most recent data
        }
        
        # Search across relevant Zeek indices
        # Assuming indices like "axlap-zeek-YYYY.MM.DD"
        # Construct index pattern for the last N days or use a wildcard
        index_pattern = "axlap-zeek-*" # General pattern

        try:
            res = es_client.search(index=index_pattern, body=query, scroll='2m') # Added scroll for large results
            scroll_id = res['_scroll_id']
            hits = res['hits']['hits']
            
            all_docs = []
            all_docs.extend(hits)

            while len(hits) > 0 and len(all_docs) < max_samples:
                res = es_client.scroll(scroll_id=scroll_id, scroll='2m')
                hits = res['hits']['hits']
                all_docs.extend(hits)
                if len(all_docs) >= max_samples:
                    all_docs = all_docs[:max_samples]
                    break
            
            es_client.clear_scroll(scroll_id=scroll_id)
            
            print(f"Fetched {len(all_docs)} documents.")
            return [doc['_source'] for doc in all_docs] # Return list of source documents
        except Exception as e:
            print(f"Error fetching data from Elasticsearch: {e}")
            return []

def main():
        print("Starting ML Model Training for Connection Anomaly Detection...")

        try:
            es = Elasticsearch([{'host': ES_HOST, 'port': ES_PORT, 'scheme': 'http'}])
            if not es.ping():
                raise ConnectionError("Failed to connect to Elasticsearch")
        except Exception as e:
            print(f"Elasticsearch connection error: {e}")
            return

        # 1. Fetch data
        raw_data = fetch_data_from_es(es, days_ago=TRAINING_DAYS, max_samples=MAX_TRAINING_SAMPLES)
        if not raw_data:
            print("No data fetched. Aborting training.")
            return

        # 2. Preprocess data and create features
        df = create_feature_df(raw_data)
        if df.empty:
            print("DataFrame is empty after preprocessing. Aborting training.")
            return

        # Ensure correct features are selected and ordered
        X = get_features_for_prediction(df.copy())
        print(f"Training with {X.shape[0]} samples and {X.shape[1]} features.")
        print(f"Features: {X.columns.tolist()}")


        # 3. Scale numerical features
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)

        # 4. Train Isolation Forest model
        # Contamination: expected proportion of outliers. 'auto' or a float.
        # Adjust based on expected anomaly rate in your data.
        model = IsolationForest(n_estimators=100, contamination='auto', random_state=42, n_jobs=-1)
        print("Training Isolation Forest model...")
        model.fit(X_scaled)
        print("Model training complete.")

        # 5. Save the model and scaler
        os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
        joblib.dump(model, MODEL_PATH)
        joblib.dump(scaler, SCALER_PATH)
        print(f"Model saved to {MODEL_PATH}")
        print(f"Scaler saved to {SCALER_PATH}")

if __name__ == "__main__":
        main()
