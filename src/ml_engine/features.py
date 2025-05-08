import pandas as pd
import numpy as np

def preprocess_conn_log_entry(entry):
        """Converts a single conn.log entry (dict) to a feature dict."""
        features = {}
        source = entry.get('_source', entry) # Handle docs from ES or raw logs

        features['duration'] = float(source.get('duration', 0) or 0) # Handle None
        features['orig_bytes'] = int(source.get('orig_bytes', 0) or 0)
        features['resp_bytes'] = int(source.get('resp_bytes', 0) or 0)
        features['orig_pkts'] = int(source.get('orig_pkts', 0) or 0)
        features['resp_pkts'] = int(source.get('resp_pkts', 0) or 0)
        
        # Service: one-hot encode common services, or use frequency encoding
        # For simplicity, treat unknown services as a category or ignore for now
        # services = ['http', 'dns', 'ssh', 'smtp', 'ftp'] # Example common
        # for s in services:
        #     features[f'service_{s}'] = 1 if source.get('service') == s else 0
        # Or, just use categorical encoding if model supports it, or skip for pure numerical model first.
        
        # Protocol: (tcp, udp, icmp)
        features['proto_tcp'] = 1 if source.get('proto') == 'tcp' else 0
        features['proto_udp'] = 1 if source.get('proto') == 'udp' else 0
        features['proto_icmp'] = 1 if source.get('proto') == 'icmp' else 0

        # Connection state: (e.g. S0, SF, REJ) - can be many, use top N or group them
        # For simplicity, skip conn_state for initial model

        # Calculated features
        features['total_bytes'] = features['orig_bytes'] + features['resp_bytes']
        features['total_pkts'] = features['orig_pkts'] + features['resp_pkts']
        
        if features['duration'] > 0:
            features['orig_Bps'] = features['orig_bytes'] / features['duration']
            features['resp_Bps'] = features['resp_bytes'] / features['duration']
            features['orig_pps'] = features['orig_pkts'] / features['duration']
            features['resp_pps'] = features['resp_pkts'] / features['duration']
        else:
            features['orig_Bps'] = 0
            features['resp_Bps'] = 0
            features['orig_pps'] = 0
            features['resp_pps'] = 0
            
        if features['total_bytes'] > 0:
            features['byte_ratio_orig_to_total'] = features['orig_bytes'] / features['total_bytes']
        else:
            features['byte_ratio_orig_to_total'] = 0.5 # Neutral if no bytes

        return features

def create_feature_df(conn_log_entries):
        """Creates a Pandas DataFrame of features from a list of conn.log entries."""
        processed_entries = [preprocess_conn_log_entry(entry) for entry in conn_log_entries]
        df = pd.DataFrame(processed_entries)
        
        # Ensure all expected columns exist, fill NaNs (e.g., if a service was never seen)
        # This depends on the full feature set defined. For now, numericals are handled.
        df.fillna(0, inplace=True) # Fill any NaNs with 0
        return df

    # Define the list of feature names the model will expect (order matters for some models)
    # This should match the output of preprocess_conn_log_entry keys
NUMERICAL_FEATURES = [
        'duration', 'orig_bytes', 'resp_bytes', 'orig_pkts', 'resp_pkts',
        'proto_tcp', 'proto_udp', 'proto_icmp',
        'total_bytes', 'total_pkts', 'orig_Bps', 'resp_Bps',
        'orig_pps', 'resp_pps', 'byte_ratio_orig_to_total'
    ]
    # Add categorical features if using them, e.g. one-hot encoded services
FEATURE_COLUMNS = NUMERICAL_FEATURES # + CATEGORICAL_FEATURES

def get_features_for_prediction(df):
        """Selects and orders columns for prediction, handles missing columns."""
        # Ensure all FEATURE_COLUMNS are present, adding them with 0 if missing
        for col in FEATURE_COLUMNS:
            if col not in df.columns:
                df[col] = 0
        return df[FEATURE_COLUMNS]
