import pandas as pd
import numpy as np
import coremltools as ct
from xgboost import XGBRegressor
from sklearn.model_selection import cross_val_score, GridSearchCV, KFold, train_test_split
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
import relevance_noise
import warnings
warnings.filterwarnings('ignore')

# 1) Load and prepare data --------------------------------------------------------------------

# Load the training data
df_relevance = pd.read_csv('synthetic_relevance.csv')
# Derive distinct id counts for theme / fclass
feature_cols = [
    "distance", "speed", "weather", "isOpen", "favorite",
    "clickCount", "lastClickedDate", "theme", "fclass", "hasName", "hasOpeningHours"
]
X_relevance = df_relevance[feature_cols]
Y_relevance = df_relevance['interestScore']

# 2) Insert Noise and load the data for training ----------------------------------------------
train_aug = relevance_noise.augmented(df_relevance, n_copies=1, flip_p=0.15, cont_frac=0.15)

X_train_full = train_aug[feature_cols]
Y_train_full = train_aug["interestScore"]

# Split augmented data for proper validation (80/20 split)
X_train, X_val, Y_train, Y_val = train_test_split(
    X_train_full,
    Y_train_full,
    test_size=0.2,
    random_state=42
)

# 3) Model config & training ------------------------------------------------------------------

# Define monotonic constraints
monotone_constraints = {
    0: -1,  # distance: higher distance -> lower score
    1: 0,   # speed: no clear monotonic relationship
    2: 0,   # weather: no clear monotonic relationship
    3: 1,   # isOpen: open -> higher score
    4: 1,   # favorite: favorite -> higher score
    5: 1,   # clickCount: more clicks -> higher score
    6: 0,   # lastClickedDate: complex relationship
    7: 0,   # theme: categorical, no monotonicity
    8: 0,   # fclass: categorical, no monotonicity
    9: 1,   # hasName: having name -> higher score
    10: 1,  # hasOpeningHours: having hours -> higher score
}

# Convert to the format XGBoost expects (tuple of constraints in feature order)
monotone_constraints_tuple = tuple(monotone_constraints[i] for i in range(len(feature_cols)))

# Initial model with your original parameters
initial_model = XGBRegressor(
    n_estimators=300,
    max_depth=4,
    objective='reg:logistic',  # This bounds output to [0,1]
    subsample=0.5,
    colsample_bytree=0.5,
    learning_rate=0.03,
    monotone_constraints=monotone_constraints_tuple,
    random_state=42  #for reproducibility
)

# Use KFold for regression (not stratified)
cv_strategy = KFold(n_splits=5, shuffle=True, random_state=42)

# Perform cross-validation on training set only
cv_scores = cross_val_score(
    initial_model,
    X_train,
    Y_train,
    cv=cv_strategy,
    scoring='neg_mean_squared_error',  # For regression
    n_jobs=-1
)

# Convert negative MSE to RMSE for interpretability
cv_rmse = np.sqrt(-cv_scores)

print(f"\nInitial Model Cross-Validation Results:")
print(f"  Mean RMSE: {cv_rmse.mean():.4f}")
print(f"  Std Deviation: {cv_rmse.std():.4f}")
print(f"  95% CI: [{cv_rmse.mean() - 2*cv_rmse.std():.4f}, {cv_rmse.mean() + 2*cv_rmse.std():.4f}]")
print(f"  Min/Max: [{cv_rmse.min():.4f}, {cv_rmse.max():.4f}]")

# 4) Hyperparameter Tuning --------------------------------------------------------------------

# Parameter grid for regression
param_grid = {
    'n_estimators': [400, 600, 1200],
    'max_depth': [3, 4, 5],
    'learning_rate': [0.03, 0.05, 0.08],
    'subsample': [0.6, 0.7, 0.8],
    'colsample_bytree': [0.6, 0.7, 0.8],
    'min_child_weight': [1, 3, 5],  # Regularization
    'gamma': [0, 0.05, 0.1],  # Regularization
    'monotone_constraints': [monotone_constraints_tuple],  # Keep constraints
    'random_state': [42]
}

# Calculate total combinations
total_combinations = 1
for key, values in param_grid.items():
    if key not in ['monotone_constraints', 'random_state']:
        total_combinations *= len(values)

# Grid Search with cross-validation
grid_search = GridSearchCV(
    XGBRegressor(),
    param_grid,
    cv=KFold(n_splits=3, shuffle=True, random_state=42),  # 3-fold for speed
    scoring='neg_mean_squared_error',  # For regression
    n_jobs=-1,
    verbose=1,
    return_train_score=True
)
grid_search.fit(X_train, Y_train)

# Check for overfitting
best_idx = grid_search.best_index_
train_score = np.sqrt(-grid_search.cv_results_['mean_train_score'][best_idx])
val_score = np.sqrt(-grid_search.cv_results_['mean_test_score'][best_idx])

print(f"\nOverfitting Check:")
print(f"  Training RMSE:   {train_score:.4f}")
print(f"  Validation RMSE: {val_score:.4f}")
print(f"  Gap:             {val_score - train_score:.4f}")

if val_score - train_score > 0.08:
    print("  Warning: Model might be overfitting")
else:
    print("  Good generalization")

# 5) Train Final Model -------------------------------------------------------------------------

# Get best model from grid search
best_model = grid_search.best_estimator_

# Retrain on full augmented dataset for final model
best_model.fit(X_train_full, Y_train_full)

# Validate on holdout set
Y_pred = best_model.predict(X_val)

# Calculate regression metrics
mse = mean_squared_error(Y_val, Y_pred)
rmse = np.sqrt(mse)
mae = mean_absolute_error(Y_val, Y_pred)
r2 = r2_score(Y_val, Y_pred)

print(f"\nFinal Model Performance:")
print(f"  RMSE: {rmse:.4f}")
print(f"  MAE:  {mae:.4f}")
print(f"  R²:   {r2:.4f}")

# Check prediction range
print(f"\nPrediction Statistics:")
print(f"  Actual range:    [{Y_val.min():.3f}, {Y_val.max():.3f}]")
print(f"  Predicted range: [{Y_pred.min():.3f}, {Y_pred.max():.3f}]")
print(f"  Mean actual:     {Y_val.mean():.3f}")
print(f"  Mean predicted:  {Y_pred.mean():.3f}")

# 6) Feature Importance ------------------------------------------------------------------------

print("\nFeature Importance:")
feature_importance = best_model.feature_importances_
importance_df = pd.DataFrame({
    'feature': feature_cols,
    'importance': feature_importance
}).sort_values('importance', ascending=False)

for _, row in importance_df.iterrows():
    bar = "█" * int(row['importance'] * 30)
    print(f"  {row['feature']:15} {row['importance']:.3f} {bar}")

# 7) Convert to Core ML ------------------------------------------------------------------------

try:
    mlmodel = ct.converters.xgboost.convert(
        best_model,
        feature_names=feature_cols,
        target='interestScore'
    )

    # Add metadata
    mlmodel.author = "MyPlaces App"
    mlmodel.short_description = "POI relevance prediction model"
    mlmodel.version = "2.0"

    save_path = "/Users/jonguler/Library/Mobile Documents/com~apple~CloudDocs/Persönlich/8 Schule/Uni/3 Arbeiten/Masterarbeit/App Programming/MyPlaces/MyPlaces/Resources/Relevance.mlmodel"
    mlmodel.save(save_path)
    print("Model saved successfully to: Relevance.mlmodel")

except Exception as e:
    print(f"Error saving model: {e}")