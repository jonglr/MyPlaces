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
                 fclass_mapping_path='fclass_mapping.json',
                 non_clustering_path='fclass_non_clustering.json'):

        self.gis = gis_connection
        self.feature_layer = FeatureLayer(feature_layer_url)
        
        # Load fclass mapping (should have 167 unique classes)
        with open(fclass_mapping_path, 'r') as f:
            self.fclass_mapping = json.load(f)
        
        # Load non-clustering fclasses (hospitals, pharmacies, etc.)
        with open(non_clustering_path, 'r') as f:
            self.non_clustering_fclasses = set(json.load(f))
        
        # Parameters
        self.cluster_eps_m = 100  # 100 meters for clustering
        self.colocation_dist_m = 200  # 200 meters for co-location
        self.lambda_param = 0.5  # λ = 0.5 for distance decay
        self.min_samples = 3  # Minimum 3 entities for a cluster
        
        # Co-location parameters
        self.prevalence_threshold = 0.33  # θ = 0.33 (one third)
        self.conditional_prob_threshold = 0.33  # α = 0.33 (33% probability)
        
        print(f"Loaded {len(self.fclass_mapping)} fclass types")
        print(f"Non-clustering types: {len(self.non_clustering_fclasses)}")
        
        # Generate co-location rules
        self.colocation_rules = self._generate_comprehensive_rules()

    # Generate comprehensive co-location rules based on urban planning logic
    def _generate_comprehensive_rules(self):
        rules = []
        
        # Define logical co-location patterns
        patterns = [
            # Accommodation needs services
            ('hotel', ['restaurant', 'cafe', 'atm', 'taxi', 'bar']),
            ('hostel', ['restaurant', 'supermarket', 'atm']),
            ('motel', ['restaurant', 'fast_food', 'atm']),
            
            # Food establishments cluster together
            ('restaurant', ['bar', 'cafe', 'atm', 'taxi']),
            ('fast_food', ['convenience', 'atm']),
            ('cafe', ['bakery', 'restaurant']),
            ('bar', ['restaurant', 'nightclub', 'fast_food']),
            
            # Shopping areas
            ('supermarket', ['atm', 'pharmacy', 'bakery', 'convenience']),
            ('mall', ['restaurant', 'cafe', 'cinema', 'atm']),
            ('department_store', ['cafe', 'restaurant', 'atm']),
            
            # Transport hubs
            ('railway_station', ['taxi', 'bus_stop', 'cafe', 'kiosk', 'atm']),
            ('bus_station', ['taxi', 'kiosk', 'convenience']),
            ('bus_stop', ['kiosk', 'convenience']),
            
            # Tourist areas
            ('museum', ['cafe', 'restaurant', 'gift_shop', 'tourist_info']),
            ('attraction', ['restaurant', 'cafe', 'souvenir', 'hotel']),
            ('monument', ['cafe', 'tourist_info']),
            ('castle', ['restaurant', 'cafe', 'gift_shop']),
            
            # Education
            ('university', ['library', 'cafe', 'bookshop', 'copy_shop']),
            ('school', ['stationery', 'bookshop']),
            
            # Healthcare (even though they don't cluster themselves)
            ('hospital', ['pharmacy', 'cafe', 'florist']),
            ('clinic', ['pharmacy']),
            
            # Entertainment
            ('cinema', ['restaurant', 'bar', 'fast_food']),
            ('theatre', ['restaurant', 'bar', 'cafe']),
            ('nightclub', ['bar', 'fast_food', 'taxi']),
        ]
        
        # Convert patterns to rules
        for premise, conclusions in patterns:
            for conclusion in conclusions:
                # Only add if both types exist in our mapping
                if premise in self.fclass_mapping and conclusion in self.fclass_mapping:
                    rules.append({'premise': premise, 'conclusion': conclusion})
        
        print(f"Generated {len(rules)} co-location rules")
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
            # Check if this is a non-clustering type
            if fclass in self.non_clustering_fclasses:
                # Assign score of 1.0 to non-clustering amenities
                features_df.loc[features_df['fclass'] == fclass, 'cluster_score'] = 1.0
                continue
            
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
            else:
                # Not enough points for clustering
                labels = np.array([-1] * len(fclass_pois))
            
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
                
                # Component 1: Cluster membership
                if label != -1:  # Part of a cluster
                    cluster_size = np.sum(labels == label)
                    # Normalize by expected cluster size (use 10 as reasonable max)
                    cluster_component = min(cluster_size / 10.0, 1.0)
                else:
                    cluster_component = 0.0
                
                # Component 2: Distance decay function
                if dist_m < np.inf:
                    # δ_ClustDist(q,g) with λ = 0.5
                    if dist_m <= self.cluster_eps_m:
                        # Within threshold: higher score for closer neighbors
                        distance_component = np.exp(-self.lambda_param * dist_m / self.cluster_eps_m)
                    else:
                        # Beyond threshold: rapid decay
                        distance_component = np.exp(-2 * dist_m / self.cluster_eps_m) * 0.5
                else:
                    distance_component = 0.0
                
                # Combine components (geometric mean)
                if cluster_component > 0 and distance_component > 0:
                    score = np.sqrt(cluster_component * distance_component)
                else:
                    score = max(cluster_component, distance_component) * 0.5
                
                # Get original index and assign score
                original_idx = fclass_pois.index[idx]
                features_df.loc[original_idx, 'cluster_score'] = min(score, 1.0)
        
        return features_df
    
    def compute_colocation_score(self, features_df):
        print("Computing co-location scores ...")
        features_df['colocation_score'] = 0.0
        
        # Build spatial index for all POIs
        all_coords = features_df[['x', 'y']].values
        all_tree = spatial.KDTree(all_coords)
        
        # Process each POI
        for idx in tqdm(features_df.index, desc="Processing co-locations"):
            poi = features_df.loc[idx]
            poi_type = poi['fclass']
            poi_coord = np.array([poi['x'], poi['y']])
            
            # Find applicable rules
            applicable_rules = [r for r in self.colocation_rules 
                               if r['premise'] == poi_type]
            
            if not applicable_rules:
                continue
            
            # Find all neighbors within 200m
            radius_degrees = self.colocation_dist_m
            neighbor_indices = all_tree.query_ball_point(poi_coord, radius_degrees)
            neighbor_indices = [i for i in neighbor_indices if i != idx]  # Exclude self
            
            if not neighbor_indices:
                continue
            
            neighbors = features_df.iloc[neighbor_indices]
            
            # Evaluate each rule
            rule_scores = []
            for rule in applicable_rules:
                conclusion_type = rule['conclusion']
                conclusion_neighbors = neighbors[neighbors['fclass'] == conclusion_type]
                
                if len(conclusion_neighbors) == 0:
                    continue
                
                # Calculate distances to conclusion type POIs
                conclusion_coords = conclusion_neighbors[['x', 'y']].values
                distances = np.sqrt(np.sum((conclusion_coords - poi_coord)**2, axis=1))
                distances_m = distances
                
                # Prevalence: how many conclusion POIs are nearby
                prevalence = len(conclusion_neighbors) / max(len(neighbors), 1)
                
                # Conditional probability: proximity-weighted
                min_dist = distances_m.min()
                proximity_score = np.exp(-min_dist / self.colocation_dist_m)
                
                # Check thresholds
                if prevalence >= self.prevalence_threshold:
                    # Strong co-location pattern
                    rule_score = min(prevalence + proximity_score * 0.5, 1.0)
                elif proximity_score >= self.conditional_prob_threshold:
                    # Proximity-based co-location
                    rule_score = proximity_score * 0.7
                else:
                    rule_score = 0.0
                
                if rule_score > 0:
                    rule_scores.append(rule_score)
            
            # Aggregate rule scores
            if rule_scores:
                # Use mean of top 3 rules (avoid dilution from many weak rules)
                top_scores = sorted(rule_scores, reverse=True)[:3]
                features_df.loc[idx, 'colocation_score'] = np.mean(top_scores)
        
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
            print("\n" + "="*60)
            print("SCORE STATISTICS:")
            print("-"*60)
            
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
            print("\n" + "="*60)
            print("TOP SCORING POIS:")
            print("-"*60)
            
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
            print("\n" + "="*60)
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
            print(f"\n" + "="*60)
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

        output_file = f"scores_{len(features_df)}_features.csv"
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
    passwords = match.group(1)

# Usage
if __name__ == "__main__":
    print("="*60)
    print("Attribute Calculator")
    print("="*60)
    
    # Connect to ArcGIS
    gis = GIS("https://www.arcgis.com", username="jonglr", password=password)
    
    feature_layer_url = "https://services.arcgis.com/wg31rjAWgC3uC62p/arcgis/rest/services/OSM_POI/FeatureServer/0"

    # Initialize processor
    processor = GeographicProcessor(
        feature_layer_url,
        gis,
        fclass_mapping_path='fclass_mapping.json',
        non_clustering_path='fclass_non_clustering.json'
    )
    
    # Process
    processed_df = processor.process(
        prevent_sleep=True
    )