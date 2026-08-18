"""
Medication Intake Camera Tracking System
- True2D / True3D CSV data loading
- Auto labeling (hand-face proximity based)
- Feature extraction, model training and testing
"""

import os
import ast
import glob
import pickle
import numpy as np
import pandas as pd
from pathlib import Path
import matplotlib.pyplot as plt
from scipy.spatial.distance import euclidean
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report
import warnings
warnings.filterwarnings('ignore')


class Config:
    HAND_FACE_THRESHOLD_2D  = 80
    HAND_FACE_THRESHOLD_3D  = 0.30
    WRIST_HEIGHT_RATIO      = 0.6
    MIN_CONSECUTIVE_FRAMES  = 3

    DATA_ROOT  = r"C:\Users\user\Desktop\ai\dataset"
    VIDEO_DIR  = os.path.join(DATA_ROOT, "deepfaked")
    CSV_2D_DIR = os.path.join(DATA_ROOT, "True2D")
    CSV_3D_DIR = os.path.join(DATA_ROOT, "True3D")
    BASE_DIR = Path(__file__).parent

    OUTPUT_DIR = BASE_DIR / "models"

    MODEL_PATH = OUTPUT_DIR / "medication_model.pkl"

class DataLoader:
    @staticmethod
    def parse_tuple(val):
        if isinstance(val, tuple):
            return val
        try:
            return ast.literal_eval(str(val).strip())
        except Exception:
            return (np.nan, np.nan)

    @staticmethod
    def load_2d(csv_path):
        df = pd.read_csv(csv_path)
        for col in ['head','Mid-Shoulder','Right-Shoulder','Right-Elbow',
                    'Right-Wrist','Left-shoulder','Left-Elbow','Left-Wrist']:
            if col in df.columns:
                parsed = df[col].apply(DataLoader.parse_tuple)
                df[f'{col}_x'] = parsed.apply(lambda t: t[0])
                df[f'{col}_y'] = parsed.apply(lambda t: t[1])
        df['source_file'] = os.path.basename(csv_path)
        return df

    @staticmethod
    def load_3d(csv_path):
        df = pd.read_csv(csv_path, index_col=0)
        df['source_file'] = os.path.basename(csv_path)
        return df

    @staticmethod
    def find_pairs(csv_2d_dir, csv_3d_dir):
        pairs = []
        for f2d in glob.glob(os.path.join(csv_2d_dir, "*.csv")):
            base    = os.path.basename(f2d)
            date_id = base.split('.mp4')[0] if '.mp4' in base else base.split('_preds')[0]
            f3d     = glob.glob(os.path.join(csv_3d_dir, f"{date_id}*.csv"))
            pairs.append({'date_id': date_id, 'path_2d': f2d,
                          'path_3d': f3d[0] if f3d else None})
        return pairs


class AutoLabeler:
    def __init__(self, cfg=Config()):
        self.cfg = cfg

    def label_2d(self, df):
        df = df.copy()
        labels = []
        for _, row in df.iterrows():
            hx, hy = row.get('head_x', np.nan), row.get('head_y', np.nan)
            scores = []
            for side in ['Right-Wrist', 'Left-Wrist']:
                wx, wy = row.get(f'{side}_x', np.nan), row.get(f'{side}_y', np.nan)
                if np.isnan(wx) or np.isnan(hx): continue
                dist = euclidean([wx,wy],[hx,hy])
                scores.append(dist < self.cfg.HAND_FACE_THRESHOLD_2D and
                               wy <= hy * (1 + self.cfg.WRIST_HEIGHT_RATIO))
            labels.append(1 if any(scores) else 0)
        df['raw_label'] = labels
        df['label']     = self._smooth(labels)
        return df

    def label_3d(self, df):
        df = df.copy()
        labels = []
        for _, row in df.iterrows():
            hx = row.get('head_x', np.nan)
            hy = row.get('head_y', np.nan)
            hz = row.get('head_z', np.nan)
            scores = []
            for side in ['Right-Wrist', 'Left-Wrist']:
                wx = row.get(f'{side}_x', np.nan)
                wy = row.get(f'{side}_y', np.nan)
                wz = row.get(f'{side}_z', np.nan)
                if np.isnan(wx) or np.isnan(hx): continue
                scores.append(euclidean([wx,wy,wz],[hx,hy,hz]) < self.cfg.HAND_FACE_THRESHOLD_3D)
            labels.append(1 if any(scores) else 0)
        df['raw_label'] = labels
        df['label']     = self._smooth(labels)
        return df

    def _smooth(self, labels):
        labels, smoothed, n = list(labels), list(labels), len(labels)
        i = 0
        while i < n:
            if labels[i] == 1:
                j = i
                while j < n and labels[j] == 1: j += 1
                if j - i < self.cfg.MIN_CONSECUTIVE_FRAMES:
                    for k in range(i, j): smoothed[k] = 0
                i = j
            else:
                i += 1
        return smoothed


class FeatureExtractor:
    @staticmethod
    def extract_2d(df):
        feats = pd.DataFrame()
        hx, hy = df['head_x'], df['head_y']
        for side, p in [('Right','R'),('Left','L')]:
            wx = df.get(f'{side}-Wrist_x',    pd.Series(np.nan, index=df.index))
            wy = df.get(f'{side}-Wrist_y',    pd.Series(np.nan, index=df.index))
            ex = df.get(f'{side}-Elbow_x',    pd.Series(np.nan, index=df.index))
            ey = df.get(f'{side}-Elbow_y',    pd.Series(np.nan, index=df.index))
            sx = df.get(f'{side}-Shoulder_x', pd.Series(np.nan, index=df.index))
            sy = df.get(f'{side}-Shoulder_y', pd.Series(np.nan, index=df.index))
            feats[f'{p}_wrist_head_dist']      = np.sqrt((wx-hx)**2+(wy-hy)**2)
            feats[f'{p}_wrist_height_ratio']   = wy/(hy+1e-6)
            feats[f'{p}_elbow_angle']          = np.degrees(np.arctan2(ey-sy,ex-sx))
            feats[f'{p}_wrist_above_shoulder'] = (wy<sy).astype(int)
            feats[f'{p}_wrist_vel_x']          = wx.diff().fillna(0)
            feats[f'{p}_wrist_vel_y']          = wy.diff().fillna(0)
        feats['head_x'], feats['head_y'] = hx, hy
        return feats.fillna(0)

    @staticmethod
    def extract_3d(df):
        feats = pd.DataFrame()
        hx = df.get('head_x', pd.Series(np.nan, index=df.index))
        hy = df.get('head_y', pd.Series(np.nan, index=df.index))
        hz = df.get('head_z', pd.Series(np.nan, index=df.index))
        for side, p in [('Right','R'),('Left','L')]:
            wx = df.get(f'{side}-Wrist_x',    pd.Series(np.nan, index=df.index))
            wy = df.get(f'{side}-Wrist_y',    pd.Series(np.nan, index=df.index))
            wz = df.get(f'{side}-Wrist_z',    pd.Series(np.nan, index=df.index))
            ex = df.get(f'{side}-Elbow_x',    pd.Series(np.nan, index=df.index))
            ey = df.get(f'{side}-Elbow_y',    pd.Series(np.nan, index=df.index))
            ez = df.get(f'{side}-Elbow_z',    pd.Series(np.nan, index=df.index))
            sx = df.get(f'{side}-Shoulder_x', pd.Series(np.nan, index=df.index))
            sy = df.get(f'{side}-Shoulder_y', pd.Series(np.nan, index=df.index))
            sz = df.get(f'{side}-Shoulder_z', pd.Series(np.nan, index=df.index))
            feats[f'{p}_wrist_head_dist3d']  = np.sqrt((wx-hx)**2+(wy-hy)**2+(wz-hz)**2)
            feats[f'{p}_wrist_depth_diff']   = wz-hz
            feats[f'{p}_wrist_height_ratio'] = wy/(hy+1e-6)
            feats[f'{p}_elbow_z_angle']      = np.degrees(np.arctan2(ez-sz,ex-sx))
            feats[f'{p}_wrist_vel_x']        = wx.diff().fillna(0)
            feats[f'{p}_wrist_vel_y']        = wy.diff().fillna(0)
            feats[f'{p}_wrist_vel_z']        = wz.diff().fillna(0)
        return feats.fillna(0)


class MedicationDetector:
    def __init__(self):
        self.scaler        = StandardScaler()
        self.model         = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                                        learning_rate=0.05, random_state=42)
        self.feature_names = []

    def train(self, X, y, verbose=True):
        self.feature_names = list(X.columns)
        Xs = self.scaler.fit_transform(X)
        X_tr, X_val, y_tr, y_val = train_test_split(Xs, y, test_size=0.2,
                                                      stratify=y, random_state=42)
        self.model.fit(X_tr, y_tr)
        if verbose:
            cv = cross_val_score(self.model, Xs, y, cv=5, scoring='f1')
            print(f"\n[Training Complete]  CV F1: {cv.mean():.3f} +/- {cv.std():.3f}")
            print(classification_report(y_val, self.model.predict(X_val),
                                        target_names=['Normal(0)','Intake(1)']))
        return self

    def predict(self, X):
        return self.model.predict(self.scaler.transform(X[self.feature_names]))

    def predict_proba(self, X):
        return self.model.predict_proba(self.scaler.transform(X[self.feature_names]))[:,1]

    # ── Save / Load ──────────────────────────────
    def save(self, path=Config.MODEL_PATH):
        os.makedirs(os.path.dirname(path) if os.path.dirname(path) else '.', exist_ok=True)
        with open(path, 'wb') as f:
            pickle.dump({'model': self.model, 'scaler': self.scaler,
                         'feature_names': self.feature_names}, f)
        print(f"[Saved] Model -> {path}")

    @classmethod
    def load(cls, path=Config.MODEL_PATH):
        with open(path, 'rb') as f:
            data = pickle.load(f)
        obj = cls()
        obj.model, obj.scaler, obj.feature_names = data['model'], data['scaler'], data['feature_names']
        print(f"[Loaded] Model <- {path}")
        return obj

    def feature_importance_plot(self, save_path=None):
        imp = self.model.feature_importances_
        idx = np.argsort(imp)[::-1][:15]
        fig, ax = plt.subplots(figsize=(10,5))
        ax.bar(range(len(idx)), imp[idx])
        ax.set_xticks(range(len(idx)))
        ax.set_xticklabels([self.feature_names[i] for i in idx], rotation=45, ha='right')
        ax.set_title("Feature Importance (Top 15)")
        ax.set_ylabel("Importance")
        plt.tight_layout()
        if save_path:
            plt.savefig(save_path, dpi=150)
        plt.show()


def plot_timeline(df, title="Medication Intake Timeline"):
    fig, axes = plt.subplots(3, 1, figsize=(14,8), sharex=True)
    frames = df.index
    r_col = 'R_wrist_head_dist' if 'R_wrist_head_dist' in df.columns else 'R_wrist_head_dist3d'
    l_col = 'L_wrist_head_dist' if 'L_wrist_head_dist' in df.columns else 'L_wrist_head_dist3d'
    if r_col in df.columns:
        axes[0].plot(frames, df[r_col], label='Right wrist-face dist', color='steelblue')
    if l_col in df.columns:
        axes[0].plot(frames, df[l_col], label='Left wrist-face dist',  color='coral')
    axes[0].set_ylabel("Wrist-Face Distance"); axes[0].legend(fontsize=8); axes[0].grid(alpha=0.3)
    if 'label' in df.columns:
        axes[1].fill_between(frames, df['label'], alpha=0.7, color='green', label='Intake(1)')
        axes[1].set_ylabel("Ground Truth"); axes[1].set_ylim(-0.1,1.3)
        axes[1].legend(fontsize=8); axes[1].grid(alpha=0.3)
    if 'pred_label' in df.columns:
        axes[2].fill_between(frames, df['pred_label'], alpha=0.7, color='orange', label='Prediction')
        if 'label' in df.columns:
            axes[2].fill_between(frames, df['label'], alpha=0.3, color='green', label='Ground Truth')
        axes[2].set_ylabel("Pred vs GT"); axes[2].set_ylim(-0.1,1.3)
        axes[2].legend(fontsize=8); axes[2].grid(alpha=0.3)
    axes[-1].set_xlabel("Frame")
    fig.suptitle(title, fontsize=13)
    plt.tight_layout()
    plt.savefig(os.path.join(Config.OUTPUT_DIR, "timeline.png"), dpi=150)
    plt.show()


def run_pipeline(use_3d=True, demo_mode=True):
    os.makedirs(Config.OUTPUT_DIR, exist_ok=True)
    labeler, extractor = AutoLabeler(), FeatureExtractor()

    if demo_mode:
        print("=" * 50)
        print("  [DEMO MODE] Running with synthetic data")
        print("=" * 50)
        np.random.seed(42); N = 500
        df3d = pd.DataFrame({
            'head_x': np.random.normal(0.6,0.05,N), 'head_y': np.random.normal(0.47,0.02,N),
            'head_z': np.random.normal(2.0,0.05,N),
            'Right-Wrist_x': np.random.normal(0.85,0.1,N), 'Right-Wrist_y': np.random.normal(0.05,0.15,N),
            'Right-Wrist_z': np.random.normal(2.45,0.1,N), 'Left-Wrist_x':  np.random.normal(0.38,0.1,N),
            'Left-Wrist_y':  np.random.normal(0.05,0.15,N),'Left-Wrist_z':  np.random.normal(2.62,0.1,N),
            'Right-Elbow_x': np.random.normal(0.85,0.05,N),'Right-Elbow_y': np.random.normal(0.25,0.05,N),
            'Right-Elbow_z': np.random.normal(2.38,0.05,N),'Left-Elbow_x':  np.random.normal(0.42,0.05,N),
            'Left-Elbow_y':  np.random.normal(0.28,0.05,N),'Left-Elbow_z':  np.random.normal(2.48,0.05,N),
            'Right-Shoulder_x': np.random.normal(0.75,0.03,N),'Right-Shoulder_y': np.random.normal(0.44,0.02,N),
            'Right-Shoulder_z': np.random.normal(2.18,0.03,N),'Left-Shoulder_x':  np.random.normal(0.49,0.03,N),
            'Left-Shoulder_y':  np.random.normal(0.47,0.02,N),'Left-Shoulder_z':  np.random.normal(2.25,0.03,N),
        })
        for s, e in [(200,250),(370,400)]:
            df3d.loc[s:e,'Right-Wrist_x'] = df3d.loc[s:e,'head_x'] + np.random.normal(0.02,0.01,e-s+1)
            df3d.loc[s:e,'Right-Wrist_y'] = df3d.loc[s:e,'head_y'] + np.random.normal(0.01,0.01,e-s+1)
            df3d.loc[s:e,'Right-Wrist_z'] = df3d.loc[s:e,'head_z'] + np.random.normal(0.05,0.02,e-s+1)
        labeled = labeler.label_3d(df3d)
        vc = labeled['label'].value_counts()
        print(f"\n[Label Distribution] Normal(0): {vc.get(0,0)},  Intake(1): {vc.get(1,0)}")
        feats = extractor.extract_3d(labeled); y = labeled['label']
        detector = MedicationDetector()
        detector.train(feats, y)
        detector.save()
        labeled['pred_label'] = detector.predict(feats)
        labeled['pred_proba'] = detector.predict_proba(feats)
        fv = feats.copy(); fv['label'] = labeled['label'].values; fv['pred_label'] = labeled['pred_label'].values
        plot_timeline(fv, "[DEMO] Medication Intake Detection")
        detector.feature_importance_plot(os.path.join(Config.OUTPUT_DIR,"feature_importance.png"))
        labeled.to_csv(os.path.join(Config.OUTPUT_DIR,"labeled_demo.csv"), index=False)
        print(f"[Done] Demo finished!")
        return detector, labeled

    else:
        pairs = DataLoader.find_pairs(Config.CSV_2D_DIR, Config.CSV_3D_DIR)
        print(f"[Data] {len(pairs)} session(s) found")
        all_feats = []
        for pair in pairs:
            print(f"  Processing: {pair['date_id']}")
            try:
                if use_3d and pair['path_3d']:
                    df = DataLoader.load_3d(pair['path_3d'])
                    labeled = labeler.label_3d(df); feats = extractor.extract_3d(labeled)
                else:
                    df = DataLoader.load_2d(pair['path_2d'])
                    labeled = labeler.label_2d(df); feats = extractor.extract_2d(labeled)
                feats['label'] = labeled['label'].values; feats['date_id'] = pair['date_id']
                all_feats.append(feats)
                labeled.to_csv(os.path.join(Config.OUTPUT_DIR, f"{pair['date_id']}_labeled.csv"), index=False)
            except Exception as ex:
                print(f"    [Warning] {pair['date_id']}: {ex}")
        if not all_feats:
            print("[Error] No data processed."); return None, None
        all_df = pd.concat(all_feats, ignore_index=True)
        X = all_df.drop(columns=['label','date_id'], errors='ignore'); y = all_df['label']
        detector = MedicationDetector()
        detector.train(X, y)
        detector.save()   # <-- saves medication_model.pkl
        detector.feature_importance_plot(os.path.join(Config.OUTPUT_DIR,"feature_importance.png"))
        print(f"\n[Done] Results saved to: {Config.OUTPUT_DIR}/")
        return detector, all_df


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['demo','real'], default='demo')
    parser.add_argument('--dim',  choices=['2d','3d'],    default='3d')
    args = parser.parse_args()
    run_pipeline(use_3d=(args.dim=='3d'), demo_mode=(args.mode=='demo'))
