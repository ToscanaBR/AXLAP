import os
import joblib
import pandas as pd
from elasticsearch import Elasticsearch, helpers
from datetime import datetime, timedelta

from ml_engine.features import create_feature_df, get_features_for_prediction

    # Configuration
ES_HOST = os.getenv("ELASTICSEARCH_HOST", "axlap-elasticsearch")
ES_PORT = int(os.getenv("ELASTICSEARCH_PORT", 9200))
MODEL_PATH = os.path.join(os.path.dirname(__file__), "models/isolation_forest_conn.joblib")
SCALER_PATH = os.path.join(os.path.dirname(__file__), "models/scaler_conn.joblib")
PREDICTION_WINDOW_MINUTES = int(os.getenv("ML_PREDICTION_WINDOW_MINUTES", 15)) # Process last 15 mins of data
ALERT_INDEX_NAME = "axlap-ml-alerts" # Elasticsearch index for ML alerts
MAX_PREDICTION_SAMPLES = int(os.getenv("ML_MAX_PREDICTION_SAMPLES", 10000))

def load_model_and_scaler():
        if not os.path.exists(MODEL_PATH) or not os.path.exists(SCALER_PATH):
            print("Model or scaler not found. Run training first.")
            return None, None
        model = joblib.load(MODEL_PATH)
        scaler = joblib.load(SCALER_PATH)
        return model, scaler

def fetch_recent_data(es_client, minutes_ago=15, max_samples=10000):
        print(f"Fetching recent Zeek conn.log data (last {minutes_ago} minutes)...")
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(minutes=minutes_ago)
        
        query = {
            "query": {
                 "bool": {
                    "must": [
                        {"match": {"event.kind": "zeek_log"}},
                        {"exists": {"field": "uid"}}
                    ],
                    "filter": [
                        {
                            "range": {
                                "@timestamp": {
                                    "gte": start_date.isoformat(),
                                    "lte": end_date.isoformat()
                                }
                            }
                        }
                    ],
                    # Avoid re-processing already alerted items if we add a tag
                    # "must_not": [
                    #    {"exists": {"field": "axlap_ml_alerted"}}
                    # ]
                }
            },
            "_source": ["duration", "orig_bytes", "resp_bytes", "orig_pkts", "resp_pkts", "proto", "service", "uid", "@timestamp", "id.orig_h", "id.orig_p", "id.resp_h", "id.resp_p"],
            "size": max_samples,
            "sort": [{"@timestamp": "desc"}]
        }
        index_pattern = "axlap-zeek-*"
        try:
            res = es_client.search(index=index_pattern, body=query)
            print(f"Fetched {len(res['hits']['hits'])} documents for prediction.")
            return res['hits']['hits'] # Return full documents for context in alerts
        except Exception as e:
            print(f"Error fetching data for prediction: {e}")
            return []

def post_alerts_to_es(es_client, alerts):
        if not alerts:
            return
        
        # Create index template for alerts if it doesn't exist
        template_name = "axlap_ml_alerts_template"
        template_body = {
            "index_patterns": [f"{ALERT_INDEX_NAME}-*"],
            "mappings": {
                "properties": {
                    "timestamp": {"type": "date"},
                    "alert_type": {"type": "keyword"},
                    "anomaly_score": {"type": "float"},
                    "description": {"type": "text"},
                    "original_event": {"type": "object", "enabled": False}, # Store original event as object, not indexed deeply
                    "src_ip": {"type": "ip"},
                    "dst_ip": {"type": "ip"},
                    "dst_port": {"type": "integer"},
                    # ... other relevant fields
                }
            }
        }
        if not es_client.indices.exists_template(name=template_name):
            try:
                es_client.indices.put_template(name=template_name, body=template_body)
                print(f"Created Elasticsearch template: {template_name}")
            except Exception as e:
                print(f"Error creating template {template_name}: {e}")


        actions = []
        current_date_str = datetime.utcnow().strftime("%Y.%m.%d")
        index_name_with_date = f"{ALERT_INDEX_NAME}-{current_date_str}"

        for alert in alerts:
            action = {
                "_index": index_name_with_date,
                "_source": alert
            }
            actions.append(action)
        
        try:
            helpers.bulk(es_client, actions)
            print(f"Posted {len(alerts)} ML alerts to Elasticsearch index {index_name_with_date}.")
        except Exception as e:
            print(f"Error posting alerts to Elasticsearch: {e}")


def main():
        print("Starting ML Prediction Process...")
        model, scaler = load_model_and_scaler()
        if not model or not scaler:
            return

        try:
            es = Elasticsearch([{'host': ES_HOST, 'port': ES_PORT, 'scheme': 'http'}])
            if not es.ping():
                raise ConnectionError("Failed to connect to Elasticsearch")
        except Exception as e:
            print(f"Elasticsearch connection error: {e}")
            return

        # 1. Fetch recent data
        raw_docs = fetch_recent_data(es, minutes_ago=PREDICTION_WINDOW_MINUTES, max_samples=MAX_PREDICTION_SAMPLES)
        if not raw_docs:
            print("No recent data to predict on.")
            return

        raw_data_sources = [doc['_source'] for doc in raw_docs]
        df = create_feature_df(raw_data_sources)
        if df.empty:
            print("DataFrame is empty after preprocessing. Aborting prediction.")
            return
            
        X = get_features_for_prediction(df.copy())

        # 2. Scale features
        X_scaled = scaler.transform(X)

        # 3. Make predictions (anomaly scores and labels: -1 for anomalies, 1 for inliers)
        anomaly_scores = model.decision_function(X_scaled) # Lower scores are more anomalous
        predictions = model.predict(X_scaled) # -1 if anomaly, 1 if normal

        # 4. Create alerts for anomalies
        alerts_to_post = []
        for i, pred_label in enumerate(predictions):
            if pred_label == -1: # Anomaly detected
                original_event_source = raw_data_sources[i]
                original_event_full = raw_docs[i] # Contains _id, _index etc.

                alert = {
                    "timestamp": datetime.utcnow().isoformat(),
                    "alert_type": "ConnectionAnomaly",
                    "anomaly_score": float(anomaly_scores[i]),
                    "description": f"Anomalous network connection detected for UID: {original_event_source.get('uid', 'N/A')}",
                    "original_event_uid": original_event_source.get('uid'),
                    "original_event_timestamp": original_event_source.get('@timestamp'),
                    "src_ip": original_event_source.get('id.orig_h'),
                    "src_port": original_event_source.get('id.orig_p'),
                    "dst_ip": original_event_source.get('id.resp_h'),
                    "dst_port": original_event_source.get('id.resp_p'),
                    "proto": original_event_source.get('proto'),
                    "service": original_event_source.get('service'),
                    "duration": original_event_source.get('duration'),
                    "orig_bytes": original_event_source.get('orig_bytes'),
                    "resp_bytes": original_event_source.get('resp_bytes'),
                    "original_event_details": original_event_source # Store a copy of the original fields
                    # Consider adding original_event_es_id: original_event_full.get('_id') for linkage
                }
                alerts_to_post.append(alert)
        
        if alerts_to_post:
            post_alerts_to_es(es, alerts_to_post)
        else:
            print("No anomalies detected in the current window.")
            
        print("ML Prediction Process Finished.")

if __name__ == "__main__":
        # This script would be run by cron or a systemd timer
        # Example: */15 * * * * /opt/axlap/venv/bin/python /opt/axlap/src/ml_engine/predict.py
        main()
