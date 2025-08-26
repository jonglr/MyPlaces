import numpy as np
import pandas as pd
from xgboost import XGBClassifier
import coremltools as ct
import thematic_noise
from sklearn.model_selection import cross_val_score, GridSearchCV, StratifiedKFold, train_test_split
from sklearn.metrics import classification_report, accuracy_score
import warnings
warnings.filterwarnings('ignore')

# 1) Load the data ---------------------------------------------------------------------------

# Load the training data
df_thematic = pd.read_csv('synthetic_thematic.csv')
X_thematic = df_thematic[["environmentType", "timeOfDay", "dayOfWeek"]]
Y_thematic   = df_thematic["themeLabel"]

# Add noise to the data to train
train_aug = thematic_noise.augmented(df_thematic, n_copies=3, flip_p=0.3)

feature_cols = [
    "environmentType", "timeOfDay", "dayOfWeek",
]
X_train_full = train_aug[feature_cols]
Y_train_full = train_aug["themeLabel"]

# Split augmented data for proper validation (80/20 split)
X_train, X_val, Y_train, Y_val = train_test_split(
    X_train_full,
    Y_train_full,
    test_size=0.2,
    random_state=42,
    stratify=Y_train_full  # Ensures balanced class distribution
)

# 3) Model config & training -----------------------------------------------------------------

# Initial model with your original parameters
initial_model = XGBClassifier(
    n_estimators=400,
    max_depth=5,
    subsample=0.6,
    colsample_bytree=0.8,
    learning_rate=0.10,
    random_state=42  # For reproducibility
)

# Use StratifiedKFold for better cross-validation with class balance
cv_strategy = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

# Perform cross-validation on training set only (not full augmented data)
cv_scores = cross_val_score(
    initial_model,
    X_train,
    Y_train,
    cv=cv_strategy,
    scoring='accuracy',
    n_jobs=-1
)

print(f"\nInitial Model Cross-Validation Results:")
print(f"  Mean Accuracy: {cv_scores.mean():.4f}")
print(f"  Std Deviation: {cv_scores.std():.4f}")
print(f"  95% CI: [{cv_scores.mean() - 2*cv_scores.std():.4f}, {cv_scores.mean() + 2*cv_scores.std():.4f}]")
print(f"  Min/Max: [{cv_scores.min():.4f}, {cv_scores.max():.4f}]")

# 4) Hyperparameter Tuning ----------------------------------------------------------------------

# More focused parameter grid based on initial results
param_grid = {
    'n_estimators': [200, 400, 600],
    'max_depth': [3, 5, 7],
    'learning_rate': [0.05, 0.1, 0.15],
    'subsample': [0.6, 0.8],
    'colsample_bytree': [0.6, 0.8],
    'min_child_weight': [1, 3],  # Added for regularization
    'gamma': [0, 0.1],  # Added for regularization
    'random_state': [42]  # Fixed for reproducibility
}

# Grid Search with proper cross-validation strategy
grid_search = GridSearchCV(
    XGBClassifier(),
    param_grid,
    cv=StratifiedKFold(n_splits=3, shuffle=True, random_state=42),  # 3-fold for speed
    scoring='accuracy',
    n_jobs=-1,
    verbose=1,
    return_train_score=True  # To check for overfitting
)

grid_search.fit(X_train, Y_train)  # Fit on training set only

for param, value in grid_search.best_params_.items():
    if param != 'random_state':  # Skip random_state in display
        print(f"  {param:20} {value}")

# Check for overfitting by comparing train and validation scores
best_idx = grid_search.best_index_
train_score = grid_search.cv_results_['mean_train_score'][best_idx]
val_score = grid_search.cv_results_['mean_test_score'][best_idx]

print(f"\nOverfitting Check:")
print(f"  Training Score:   {train_score:.4f}")
print(f"  Validation Score: {val_score:.4f}")
print(f"  Gap:              {train_score - val_score:.4f}")

if train_score - val_score > 0.05:
    print("Warning: Model might be overfitting")
else:
    print("Good generalization")

# 5) Convert to Core ML ----------------------------------------------------------------------

# Get best model from grid search
best_model = grid_search.best_estimator_

best_model.fit(X_train_full, Y_train_full)

# Validate on holdout set
Y_pred = best_model.predict(X_val)
final_accuracy = accuracy_score(Y_val, Y_pred)

print(f"\nFinal Model Performance:")
print(f"Holdout Validation Accuracy: {final_accuracy:.4f}")

# Show per-class performance
print("\nPer-Class Performance:")
theme_names = ['shopping', 'food', 'public transport', 'culture', 'outdoor', 'explore']
print(classification_report(Y_val, Y_pred, target_names=theme_names, digits=3))

# Feature Importance
print("\nFeature Importance:")
feature_importance = best_model.feature_importances_
for feature, importance in zip(feature_cols, feature_importance):
    bar = "█" * int(importance * 30)
    print(f"  {feature:15} {importance:.3f} {bar}")

try:
    mlmodel = ct.converters.xgboost.convert(
        best_model,
        feature_names=feature_cols,
        target='themeLabel',
        mode="classifier",
        class_labels=sorted(Y_train_full.unique().tolist())
    )

    # Add metadata
    mlmodel.author = "MyPlaces App"
    mlmodel.short_description = "Thematic preference prediction model"
    mlmodel.version = "2.0"

    save_path = "/Users/jonguler/Library/Mobile Documents/com~apple~CloudDocs/Persönlich/8 Schule/Uni/3 Arbeiten/Masterarbeit/App Programming/MyPlaces/MyPlaces/Resources/Thematic.mlmodel"
    mlmodel.save(save_path)
    print(f"Model saved successfully to: Thematic.mlmodel")

except Exception as e:
    print(f"Error saving model: {e}")