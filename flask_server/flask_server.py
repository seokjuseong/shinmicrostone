"""
Medication Intake Detection - Flask Inference Server
Reuses the exact same pipeline as webcam_test.py (mediapipe pose + pkl model),
but exposes it over HTTP so Flutter (Web build in Chrome, or Android emulator/device)
can send camera frames and get back predictions.

This lets you test the SAME model/logic from both:
  - Chrome (flutter run -d chrome)
  - Android emulator / real device (flutter run)
without needing onnxruntime or google_mlkit_pose_detection at all.

Requirements:
  pip install flask flask-cors mediapipe opencv-python pandas numpy

Usage:
  python flask_server.py
  # Server listens on http://0.0.0.0:5000

Endpoints:
  GET  /health            -> {"status": "ok"}
  POST /predict           -> multipart/form-data: 'frame' (jpg/png bytes), 'session_id' (str)
                              returns {label, probability, consecutive, event_count, pose_detected}
  POST /reset             -> form: 'session_id'  -> resets that session's counters/buffer
"""

import os
import sys
import time
import uuid
from pathlib import Path
from collections import deque

import cv2
import numpy as np
import pandas as pd
from flask import Flask, request, jsonify
from flask_cors import CORS

sys.path.insert(0, str(Path(__file__).parent))

try:
    import mediapipe as mp
except ImportError:
    print("[Error] mediapipe not installed. Run: pip install mediapipe")
    sys.exit(1)

from medication_tracker import Config, MedicationDetector, FeatureExtractor


# ─────────────────────────────────────────────
# Settings (mirrors webcam_test.py)
# ─────────────────────────────────────────────
HAND_FACE_DIST_THRESHOLD = 0.28
MIN_CONSECUTIVE_FRAMES   = 5
BUFFER_SIZE              = 10
SESSION_TTL_SECONDS      = 60 * 30   # drop stale sessions after 30 min idle


# ─────────────────────────────────────────────
# Pose extractor (same as webcam_test.py, minus cv2.imshow drawing overhead
# on the server side we keep drawing off by default since client doesn't need it)
# ─────────────────────────────────────────────
class PoseExtractor:
    IDX = {
        'nose':            0,
        'left_shoulder':   11,
        'right_shoulder':  12,
        'left_elbow':      13,
        'right_elbow':     14,
        'left_wrist':      15,
        'right_wrist':     16,
    }

    def __init__(self):
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose(
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
            static_image_mode=False,
        )

    def extract(self, frame_rgb):
        result = self.pose.process(frame_rgb)
        if not result.pose_landmarks:
            return None

        lm = result.pose_landmarks.landmark
        coords = {}
        for name, idx in self.IDX.items():
            coords[name] = (lm[idx].x, lm[idx].y, lm[idx].z)

        ls = coords['left_shoulder']
        rs = coords['right_shoulder']
        coords['mid_shoulder'] = ((ls[0]+rs[0])/2, (ls[1]+rs[1])/2, (ls[2]+rs[2])/2)
        return coords

    def to_feature_dict(self, coords):
        if coords is None:
            return None
        nose = coords['nose']
        return {
            'head_x': nose[0], 'head_y': nose[1], 'head_z': nose[2],
            'Right-Wrist_x': coords['right_wrist'][0],
            'Right-Wrist_y': coords['right_wrist'][1],
            'Right-Wrist_z': coords['right_wrist'][2],
            'Left-Wrist_x':  coords['left_wrist'][0],
            'Left-Wrist_y':  coords['left_wrist'][1],
            'Left-Wrist_z':  coords['left_wrist'][2],
            'Right-Elbow_x': coords['right_elbow'][0],
            'Right-Elbow_y': coords['right_elbow'][1],
            'Right-Elbow_z': coords['right_elbow'][2],
            'Left-Elbow_x':  coords['left_elbow'][0],
            'Left-Elbow_y':  coords['left_elbow'][1],
            'Left-Elbow_z':  coords['left_elbow'][2],
            'Right-Shoulder_x': coords['right_shoulder'][0],
            'Right-Shoulder_y': coords['right_shoulder'][1],
            'Right-Shoulder_z': coords['right_shoulder'][2],
            'Left-Shoulder_x':  coords['left_shoulder'][0],
            'Left-Shoulder_y':  coords['left_shoulder'][1],
            'Left-Shoulder_z':  coords['left_shoulder'][2],
        }


def rule_based_detect(coords):
    """Fallback if model prediction fails for some reason."""
    if coords is None:
        return 0, 0.0
    nose = coords['nose']
    for side in ['right_wrist', 'left_wrist']:
        w = coords[side]
        dist = np.sqrt((w[0]-nose[0])**2 + (w[1]-nose[1])**2 + (w[2]-nose[2])**2)
        if dist < HAND_FACE_DIST_THRESHOLD:
            score = max(0.0, 1.0 - dist / HAND_FACE_DIST_THRESHOLD)
            return 1, round(score, 2)
    return 0, 0.0


class FrameBuffer:
    def __init__(self, size=BUFFER_SIZE):
        self.buf = deque(maxlen=size)

    def push(self, feat_dict):
        self.buf.append(feat_dict)

    def to_dataframe(self):
        if len(self.buf) < 2:
            return None
        return pd.DataFrame(list(self.buf))


class SessionState:
    """Per-client state: feature buffer + consecutive/event counters.
    Keyed by session_id so multiple test clients (web + android) don't collide."""
    def __init__(self):
        self.frame_buf    = FrameBuffer()
        self.consecutive  = 0
        self.event_count  = 0
        self.prev_confirmed = False
        self.last_seen    = time.time()

    def touch(self):
        self.last_seen = time.time()


# ─────────────────────────────────────────────
# App setup
# ─────────────────────────────────────────────
app = Flask(__name__)
CORS(app)  # needed so Flutter Web (running on a different origin) can call this server

print("[Init] Loading pose extractor...")
pose_extractor = PoseExtractor()

print("[Init] Loading model...")
USE_MODEL = os.path.exists(Config.MODEL_PATH)
detector = None
if USE_MODEL:
    detector = MedicationDetector.load(Config.MODEL_PATH)
    print(f"  Loaded: {Config.MODEL_PATH}")
else:
    print(f"  [Warning] Model not found at {Config.MODEL_PATH} -> rule-based fallback only")

extractor = FeatureExtractor()
sessions: dict[str, SessionState] = {}


def get_session(session_id: str) -> SessionState:
    if session_id not in sessions:
        sessions[session_id] = SessionState()
    s = sessions[session_id]
    s.touch()
    return s


def cleanup_sessions():
    now = time.time()
    stale = [sid for sid, s in sessions.items() if now - s.last_seen > SESSION_TTL_SECONDS]
    for sid in stale:
        del sessions[sid]


# ─────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "model_loaded": USE_MODEL})


@app.route("/reset", methods=["POST"])
def reset():
    session_id = request.form.get("session_id", "default")
    sessions.pop(session_id, None)
    return jsonify({"reset": True, "session_id": session_id})


@app.route("/predict", methods=["POST"])
def predict():
    print("[REQUEST] /predict received")
    if "frame" not in request.files:
        print("[ERROR] frame missing")
        return jsonify({"error": "missing 'frame' file"}), 400

    session_id = request.form.get("session_id", "default")
    session = get_session(session_id)

    # Decode image
    file_bytes = np.frombuffer(request.files["frame"].read(), np.uint8)
    bgr = cv2.imdecode(file_bytes, cv2.IMREAD_COLOR)
    if bgr is None:
        return jsonify({"error": "could not decode image"}), 400

    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    coords = pose_extractor.extract(rgb)

    label, prob = 0, 0.0
    pose_detected = coords is not None

    if pose_detected:
        if USE_MODEL and detector is not None:
            feat_dict = pose_extractor.to_feature_dict(coords)
            session.frame_buf.push(feat_dict)
            df = session.frame_buf.to_dataframe()
            if df is not None:
                try:
                    feats = extractor.extract_3d(df)
                    last_row = feats.iloc[[-1]]
                    prob  = float(detector.predict_proba(last_row)[0])
                    label = int(detector.predict(last_row)[0])
                except Exception as e:
                    print(f"[predict] model inference failed, falling back: {e}")
                    label, prob = rule_based_detect(coords)
        else:
            label, prob = rule_based_detect(coords)

    # Consecutive-frame smoothing + event counting (same logic as webcam_test.py)
    if label == 1:
        session.consecutive += 1
    else:
        session.consecutive = 0

    confirmed = session.consecutive >= MIN_CONSECUTIVE_FRAMES

    if confirmed and not session.prev_confirmed:
        session.event_count += 1
    session.prev_confirmed = confirmed

    if len(sessions) % 20 == 0:
        cleanup_sessions()

    return jsonify({
        "label":         int(confirmed),
        "probability":   round(prob, 4),
        "consecutive":   session.consecutive,
        "event_count":   session.event_count,
        "pose_detected": pose_detected,
    })


if __name__ == "__main__":
    # host 0.0.0.0 so it's reachable from:
    #  - Android emulator via 10.0.2.2
    #  - real Android device on same Wi-Fi via PC's LAN IP
    #  - Chrome (flutter run -d chrome) via localhost
    app.run(host="0.0.0.0", port=5000, debug=False, threaded=True)
