import json
import numpy as np
import pandas as pd
from sklearn.cluster import DBSCAN
from scipy import spatial
from arcgis import GIS
from arcgis.features import FeatureLayer
import time
from tqdm import tqdm
import re


class GeographicProcessor:
    
    def __init__(self, feature_layer_url, gis_connection, 
                 fclass_mapping_path='fclass_mapping.json'):

        self.gis = gis_connection
        self.feature_layer = FeatureLayer(feature_layer_url)
        
        # Load fclass mapping (should have 167 unique classes)
        with open(fclass_mapping_path, 'r') as f:
            self.fclass_mapping = json.load(f)
        
        # Parameters
        self.cluster_eps_m = 100  # 100 meters for clustering
        self.colocation_dist_m = 200  # 200 meters for co-location
        self.lambda_param = 0.5  # λ = 0.5 for distance decay
        self.min_samples = 3  # Minimum 3 entities for a cluster
        
        # Co-location parameters
        self.prevalence_threshold = 0.33  # θ = 0.33 (one third)
        self.conditional_prob_threshold = 0.33  # α = 0.33 (33% probability)
        
        print(f"Loaded {len(self.fclass_mapping)} fclass types")

        # Store the path for co-location rules
        self.colocation_rules_path = 'co-location_rules_high_quality.csv'

        # Import co-location rules
        self.colocation_rules = self._generate_comprehensive_rules()

    # Import co-location rules
    def _generate_comprehensive_rules(self):
        rules = []

        try:
            print(f"Loading co-location rules from {self.colocation_rules_path}...")

            # Read the CSV file
            rules_df = pd.read_csv(self.colocation_rules_path)

            # Filter rules based on quality metrics
            min_support = 0.3  # At least 30% support
            min_lift = 1.5  # At least 1.5x more likely than random
            min_score = 0.1  # Minimum combined score

            # Apply filters
            filtered_rules = rules_df[
                (rules_df['support'] >= min_support) &
                (rules_df['lift'] >= min_lift) &
                (rules_df['score'] >= min_score)
                ]

            # Convert to rule format expected by the rest of the code
            for _, row in filtered_rules.iterrows():
                # Check if both premise and conclusion exist in fclass mapping
                if (row['premise'] in self.fclass_mapping and
                        row['conclusion'] in self.fclass_mapping):
                    rules.append({
                        'premise': row['premise'],
                        'conclusion': row['conclusion'],
                        'support': row['support'],
                        'confidence': row['confidence'],
                        'lift': row['lift'],
                        'score': row['score']
                    })

            print(f"Loaded {len(rules)} co-location rules from CSV")
            print(f"  (filtered from {len(rules_df)} total rules)")

            # Show some statistics about loaded rules
            if rules:
                premises = set(r['premise'] for r in rules)
                conclusions = set(r['conclusion'] for r in rules)
                print(f"  Unique premises: {len(premises)}")
                print(f"  Unique conclusions: {len(conclusions)}")

                # Show top 5 rules by score
                top_rules = sorted(rules, key=lambda x: x['score'], reverse=True)[:5]
                print("\n  Top 5 rules by score:")
                for r in top_rules:
                    print(f"    {r['premise']} → {r['conclusion']} (score: {r['score']:.3f})")

            return rules

        except Exception as e:
            print(f"Error loading rules from CSV: {e}")

        print(f"Generated {len(rules)} fallback co-location rules")
        return rules

    # Convert meters to degrees at given latitude
    def meters_to_degrees(self, meters, latitude=47.3769):
        meters_per_degree_lat = 111320  # More precise
        meters_per_degree_lon = 111320 * np.cos(np.radians(latitude))
        
        # Use longitude degrees as it's smaller (more conservative)
        return meters / meters_per_degree_lon


    def compute_cluster_score(self, features_df):
        print("Computing cluster scores ...")
        features_df['cluster_score'] = 0.0
        
        # Group by fclass
        for fclass in tqdm(features_df['fclass'].unique(), desc="Processing fclasses"):
            
            # Get all POIs of this type
            fclass_mask = features_df['fclass'] == fclass
            fclass_pois = features_df[fclass_mask]
            
            if len(fclass_pois) < 2:
                # Single POI can't cluster, assign low score
                features_df.loc[fclass_mask, 'cluster_score'] = 0.1
                continue
            
            # Extract coordinates
            coords = fclass_pois[['x', 'y']].to_numpy(float)

            # Run DBSCAN clustering
            if len(fclass_pois) >= self.min_samples:
                clustering = DBSCAN(
                    eps=float(self.cluster_eps_m),
                    min_samples=self.min_samples,
                    metric='euclidean'
                ).fit(coords)

                labels = clustering.labels_

                # Find the largest cluster for this fclass (Φ^cat(g))
                unique_labels = [l for l in set(labels) if l != -1]
                if unique_labels:
                    cluster_sizes = [np.sum(labels == l) for l in unique_labels]
                    max_cluster_size = max(cluster_sizes)
                else:
                    max_cluster_size = 1  # No clusters found
            else:
                labels = np.array([-1] * len(fclass_pois))
                max_cluster_size = 1
            
            # Calculate distance to nearest same-type neighbor
            if len(coords) > 1:
                tree = spatial.KDTree(coords)
                distances, indices = tree.query(coords, k=2)  # k=2 to exclude self
                nearest_distances = distances[:, 1]  # Get second closest (first is self)
            else:
                nearest_distances = np.array([np.inf])
            
            # Convert distances to meters
            nearest_distances_m = nearest_distances
            
            # Calculate scores for each POI
            for idx, (label, dist_m) in enumerate(zip(labels, nearest_distances_m)):
                score = 0.0
                
                # Cardinality
                if label != -1:  # Part of a cluster
                    current_cluster_size = np.sum(labels == label)
                    # Normalize by expected cluster size
                    delta_clustcard = (max_cluster_size - current_cluster_size) / max_cluster_size
                else:
                    delta_clustcard = 1.0 # if not in cluster

                # Distance
                if dist_m < np.inf:
                    delta_clustdist = min(dist_m / self.cluster_eps_m, 1.0)
                else:
                    delta_clustdist = 1.0

                d_clustdist = np.exp(-self.lambda_param * delta_clustdist)
                d_clustcard = 1 - delta_clustcard
                
                # Combine components (euclidean distance)
                f_clust = np.sqrt(d_clustdist**2 + d_clustcard**2) / np.sqrt(2)

                # Final Score
                if len(unique_labels) == 0:
                    score = 1.0
                elif label == -1 and delta_clustcard == 1:  # Not in cluster and alone
                    score = 0.0
                else:
                    score = f_clust

                # Assign score
                original_idx = fclass_pois.index[idx]
                features_df.loc[original_idx, 'cluster_score'] = min(score, 1.0)
        
        return features_df

    def compute_colocation_score(self, features_df):
        print("Computing co-location scores ...")
        features_df['colocation_score'] = 0.0

        # Precompute all coordinates and build KDTree
        all_coords = features_df[['x', 'y']].values
        all_tree = spatial.KDTree(all_coords)

        # Create a fast-access mapping from index to fclass
        index_to_fclass = features_df['fclass'].values

        # Pre-compute max cardinalities per rule
        max_cardinalities = {}

        for rule in self.colocation_rules:
            premise_type = rule['premise']
            conclusion_type = rule['conclusion']
            max_card = 0

            # Get indices of all premise-type POIs
            premise_indices = features_df.index[features_df['fclass'] == premise_type].tolist()
            conclusion_indices = set(features_df.index[features_df['fclass'] == conclusion_type].tolist())

            for idx in premise_indices:
                coord = all_coords[idx]
                nearby_indices = all_tree.query_ball_point(coord, self.colocation_dist_m)

                # Count how many nearby are of conclusion_type
                count = sum(1 for i in nearby_indices if i in conclusion_indices)
                max_card = max(max_card, count)

            max_cardinalities[f"{premise_type}->{conclusion_type}"] = max_card

        # Now compute scores for each POI
        for idx in tqdm(features_df.index, desc="Processing co-locations"):
            poi = features_df.loc[idx]
            poi_type = poi['fclass']
            poi_coord = np.array([poi['x'], poi['y']])

            applicable_rules = [r for r in self.colocation_rules if r['premise'] == poi_type]

            if not applicable_rules:
                features_df.at[idx, 'colocation_score'] = 1.0
                continue

            rule_scores = []

            # Find neighbors once
            nearby_indices = all_tree.query_ball_point(poi_coord, self.colocation_dist_m)
            nearby_coords = all_coords[nearby_indices]
            nearby_fclasses = index_to_fclass[nearby_indices]

            for rule in applicable_rules:
                conclusion_type = rule['conclusion']
                rule_key = f"{poi_type}->{conclusion_type}"
                max_card = max_cardinalities.get(rule_key, 1)

                if max_card == 0:
                    continue

                # Filter only conclusion-type neighbors
                matching_coords = nearby_coords[nearby_fclasses == conclusion_type]

                card_psi_x = len(matching_coords)

                if card_psi_x > 0:
                    # Compute distances and min
                    dists = np.sqrt(np.sum((matching_coords - poi_coord) ** 2, axis=1))
                    min_dist = dists.min()
                    delta_coloc_dist = min_dist / self.colocation_dist_m
                else:
                    delta_coloc_dist = 1.0

                delta_coloc_card = (max_card - card_psi_x) / max_card

                # Transform into scores
                d_coloc_dist = np.exp(-self.lambda_param * delta_coloc_dist)
                d_coloc_card = (1 / (1 + delta_coloc_card) - 0.5) * 2

                # Combine via Euclidean
                f_coloc_psi = np.sqrt(d_coloc_dist ** 2 + d_coloc_card ** 2) / np.sqrt(2)

                rule_scores.append(f_coloc_psi)

            if rule_scores:
                features_df.at[idx, 'colocation_score'] = np.mean(rule_scores)
            else:
                features_df.at[idx, 'colocation_score'] = 0.0

        return features_df
    
    def process(self, sample_size=None, prevent_sleep=True):
        start_time = time.time()
        
        # Prevent sleep on macOS
        if prevent_sleep:
            import subprocess
            import platform
            if platform.system() == 'Darwin':
                caffeinate = subprocess.Popen(['caffeinate'])
            else:
                caffeinate = None
        else:
            caffeinate = None
        
        try:
            # Query features
            print(f"Querying features from ArcGIS...")
            feature_set = self.feature_layer.query(
                where="fclass IS NOT NULL AND fclass <> ''",
                out_fields="*",
                return_geometry=True,
                result_record_count=sample_size
            )
            
            # Convert to DataFrame
            features_df = feature_set.sdf
            
            # Extract coordinates from geometry
            if 'SHAPE' in features_df.columns:
                features_df['x'] = features_df['SHAPE'].apply(lambda g: g.x if g else None)
                features_df['y'] = features_df['SHAPE'].apply(lambda g: g.y if g else None)
            
            # Clean data
            features_df = features_df.dropna(subset=['x', 'y', 'fclass'])
            
            # Ensure fid exists
            if 'fid' not in features_df.columns and 'FID' in features_df.columns:
                features_df['fid'] = features_df['FID']
            elif 'fid' not in features_df.columns:
                features_df['fid'] = features_df['OBJECTID']
            
            print(f"\nProcessing {len(features_df)} valid features")
            print(f"Unique fclass types found: {features_df['fclass'].nunique()}")
            
            # Show fclass distribution
            fclass_counts = features_df['fclass'].value_counts().head(10)
            print("\nTop 10 fclass types:")
            for fclass, count in fclass_counts.items():
                clustering_status = "x" if fclass in self.non_clustering_fclasses else "✓"
                print(f"  {clustering_status} {fclass}: {count}")
            
            # Compute scores
            features_df = self.compute_cluster_score(features_df)
            features_df = self.compute_colocation_score(features_df)
            
            # Statistics
            print("SCORE STATISTICS:")
            
            # Cluster scores
            cluster_stats = features_df['cluster_score'].describe()
            print(f"Cluster Scores:")
            print(f"  Mean:     {cluster_stats['mean']:.3f}")
            print(f"  Std Dev:  {cluster_stats['std']:.3f}")
            print(f"  Min:      {cluster_stats['min']:.3f}")
            print(f"  Max:      {cluster_stats['max']:.3f}")
            print(f"  Median:   {cluster_stats['50%']:.3f}")
            print(f"  Non-zero: {(features_df['cluster_score'] > 0).sum()} / {len(features_df)}")
            
            # Show distribution
            print(f"\n  Score Distribution:")
            print(f"    [0.0-0.2): {((features_df['cluster_score'] >= 0) & (features_df['cluster_score'] < 0.2)).sum()}")
            print(f"    [0.2-0.4): {((features_df['cluster_score'] >= 0.2) & (features_df['cluster_score'] < 0.4)).sum()}")
            print(f"    [0.4-0.6): {((features_df['cluster_score'] >= 0.4) & (features_df['cluster_score'] < 0.6)).sum()}")
            print(f"    [0.6-0.8): {((features_df['cluster_score'] >= 0.6) & (features_df['cluster_score'] < 0.8)).sum()}")
            print(f"    [0.8-1.0]: {(features_df['cluster_score'] >= 0.8).sum()}")
            
            # Co-location scores
            coloc_stats = features_df['colocation_score'].describe()
            print(f"\nCo-location Scores:")
            print(f"  Mean:     {coloc_stats['mean']:.3f}")
            print(f"  Std Dev:  {coloc_stats['std']:.3f}")
            print(f"  Min:      {coloc_stats['min']:.3f}")
            print(f"  Max:      {coloc_stats['max']:.3f}")
            print(f"  Median:   {coloc_stats['50%']:.3f}")
            print(f"  Non-zero: {(features_df['colocation_score'] > 0).sum()} / {len(features_df)}")
            
            # Examples of high-scoring POIs
            print("TOP SCORING POIS:")
            
            top_cluster = features_df.nlargest(5, 'cluster_score')[['fclass', 'name', 'cluster_score']]
            print("\nTop 5 Cluster Scores:")
            for _, row in top_cluster.iterrows():
                name = row['name'][:30] if pd.notna(row['name']) else 'Unnamed'
                print(f"  {row['fclass']:20s} | {name:30s} | {row['cluster_score']:.3f}")
            
            top_coloc = features_df.nlargest(5, 'colocation_score')[['fclass', 'name', 'colocation_score']]
            print("\nTop 5 Co-location Scores:")
            for _, row in top_coloc.iterrows():
                name = row['name'][:30] if pd.notna(row['name']) else 'Unnamed'
                print(f"  {row['fclass']:20s} | {name:30s} | {row['colocation_score']:.3f}")
            
            # Update feature layer
            print("Updating ArcGIS Feature Layer...")
            self.update_feature_layer(features_df)
            
            # Save local copy
            output_file = f'scores_{len(features_df)}_features.csv'
            features_df[['fid', 'fclass', 'name', 'cluster_score', 'colocation_score']].to_csv(
                output_file, index=False
            )
            print(f"Results saved to {output_file}")
            
            # Timing
            total_time = time.time() - start_time
            print(f"PROCESSING COMPLETE!")
            print(f"Total time: {total_time/60:.1f} minutes")
            print(f"Average time per feature: {total_time/len(features_df):.3f} seconds")
            
        finally:
            if caffeinate:
                caffeinate.terminate()
        
        return features_df
    
    def update_feature_layer(self, features_df):
        updates = [
            {'attributes': {
                'fid': int(row['fid']),
                'cluster_score': row['cluster_score'],
                'colocation_score': row['colocation_score'],
            }}
            for _, row in features_df.iterrows()
        ]

        # Update in batches
        batch_size = 500
        total = len(updates)
        done = 0

        for i in range(0, total, batch_size):
            batch = updates[i:i + batch_size]
            self.feature_layer.edit_features(updates=batch)
            done += len(batch)

        print(f"Updated {done}/{total} features successfully")

        output_file = f"scores_features.csv"
        features_df[['fid', 'fclass', 'name', 'cluster_score', 'colocation_score']].to_csv(output_file, index=False)
        print(f"Results saved to {output_file}")


# get the AGOL password
swift_file_path = '/Users/jonguler/Library/Mobile Documents/com~apple~CloudDocs/Persönlich/8 Schule/Uni/3 Arbeiten/Masterarbeit/App Programming/MyPlaces/MyPlaces/Keys.swift'

with open(swift_file_path, 'r') as file:
    content = file.read()

    # Use regex to find the AGOLpassword value
    # Pattern looks for: static let AGOLpassword = "value"
    pattern = r'static\s+let\s+AGOLpassword\s*=\s*"([^"]*)"'
    match = re.search(pattern, content)
    password = match.group(1)

# Usage
if __name__ == "__main__":
    print("Attribute Calculator")
    
    # Connect to ArcGIS
    gis = GIS("https://www.arcgis.com", username="jonglr", password=password)
    
    feature_layer_url = "https://services.arcgis.com/wg31rjAWgC3uC62p/arcgis/rest/services/OSM_POI/FeatureServer/0"

    # Initialize processor
    processor = GeographicProcessor(
        feature_layer_url,
        gis,
        fclass_mapping_path='fclass_mapping.json'
    )
    
    # Process
    processed_df = processor.process(
        prevent_sleep=True
    )