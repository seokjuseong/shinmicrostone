"""
backend/app.py

회원가입/로그인/약 CRUD 를 담당하는 MySQL 연동 백엔드 스켈레톤입니다.
lib/services/api_service.dart 의 TODO(backend) 주석과 1:1로 대응되도록
엔드포인트를 설계했습니다. 지금 당장은 프론트엔드가 이 서버를 호출하지 않고
메모리로 동작하지만, 이 서버가 준비되면 api_service.dart 의 각 메서드를
아래 엔드포인트를 호출하는 http.post/get/put/delete 호출로 바꿔치기하면 됩니다.

주의:
  - 이건 "동작하는 뼈대"이지, 프로덕션 보안 수준은 아닙니다.
    (레이트리밋, 토큰 기반 인증(JWT) 등은 추가 필요)
  - 카메라/모델 추론을 담당하는 flask_server/flask_server.py 와는
    완전히 별개의 서버입니다 (포트 8000 vs 5000).

실행 방법:
  1) mysql -u root -p < schema.sql
  2) pip install -r requirements.txt
  3) 아래 환경변수(DB_HOST 등)를 본인 MySQL 설정에 맞게 지정
  4) python app.py   # http://0.0.0.0:8000
"""

import os
import uuid
from datetime import datetime, date

import mysql.connector
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
CORS(app)

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "microstone"),
}


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def row_to_medication(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "time": row["time"],
        "date": row["date"].isoformat() if isinstance(row["date"], date) else row["date"],
        "is_done": bool(row["is_done"]),
        "taken_at": row["taken_at"].isoformat() if row["taken_at"] else None,
    }


# ───────────────────────── 인증 ─────────────────────────

@app.route("/auth/signup", methods=["POST"])
def signup():
    body = request.get_json(force=True)
    user_id = (body.get("id") or "").strip()
    password = body.get("password") or ""
    nickname = (body.get("nickname") or "사용자").strip()

    if not user_id or not password:
        return jsonify({"error": "아이디와 비밀번호를 입력해주세요."}), 400

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM users WHERE id=%s", (user_id,))
        if cur.fetchone():
            return jsonify({"error": "이미 존재하는 아이디입니다."}), 409

        cur.execute(
            "INSERT INTO users (id, password_hash, nickname) VALUES (%s, %s, %s)",
            (user_id, generate_password_hash(password), nickname),
        )
        conn.commit()
        return jsonify({"id": user_id, "nickname": nickname}), 201
    finally:
        cur.close()
        conn.close()


@app.route("/auth/login", methods=["POST"])
def login():
    body = request.get_json(force=True)
    user_id = (body.get("id") or "").strip()
    password = body.get("password") or ""

    conn = get_db()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute("SELECT * FROM users WHERE id=%s", (user_id,))
        row = cur.fetchone()
        if not row or not check_password_hash(row["password_hash"], password):
            return jsonify({"error": "아이디 또는 비밀번호가 올바르지 않습니다."}), 401
        return jsonify({"id": row["id"], "nickname": row["nickname"]})
    finally:
        cur.close()
        conn.close()


@app.route("/auth/users/<user_id>", methods=["DELETE"])
def withdraw(user_id):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("DELETE FROM users WHERE id=%s", (user_id,))  # medications는 CASCADE로 함께 삭제
        conn.commit()
        return jsonify({"deleted": True})
    finally:
        cur.close()
        conn.close()


# ───────────────────────── 약(medications) ─────────────────────────

@app.route("/medications", methods=["GET"])
def list_medications():
    user_id = request.args.get("user_id", "")
    target_date = request.args.get("date", "")

    conn = get_db()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            "SELECT * FROM medications WHERE user_id=%s AND date=%s ORDER BY time ASC",
            (user_id, target_date),
        )
        rows = cur.fetchall()
        return jsonify([row_to_medication(r) for r in rows])
    finally:
        cur.close()
        conn.close()


@app.route("/medications/summary", methods=["GET"])
def medications_summary():
    """캘린더에 표시할, 특정 달에 복용 완료된 약 이름들을 날짜별로 반환."""
    user_id = request.args.get("user_id", "")
    year = request.args.get("year", "")
    month = request.args.get("month", "")

    conn = get_db()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(
            """
            SELECT DAY(date) AS day, name FROM medications
            WHERE user_id=%s AND YEAR(date)=%s AND MONTH(date)=%s AND is_done=1
            """,
            (user_id, year, month),
        )
        result = {}
        for row in cur.fetchall():
            result.setdefault(str(row["day"]), []).append(row["name"])
        return jsonify(result)
    finally:
        cur.close()
        conn.close()


@app.route("/medications", methods=["POST"])
def add_medication():
    body = request.get_json(force=True)
    user_id = body.get("user_id")
    name = (body.get("name") or "").strip()
    time_str = body.get("time")
    date_str = body.get("date")

    if not (user_id and name and time_str and date_str):
        return jsonify({"error": "user_id, name, time, date는 필수입니다."}), 400

    med_id = f"med_{uuid.uuid4().hex[:12]}"

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO medications (id, user_id, name, time, date, is_done) "
            "VALUES (%s, %s, %s, %s, %s, 0)",
            (med_id, user_id, name, time_str, date_str),
        )
        conn.commit()
        return jsonify({
            "id": med_id, "name": name, "time": time_str,
            "date": date_str, "is_done": False, "taken_at": None,
        }), 201
    finally:
        cur.close()
        conn.close()


@app.route("/medications/<med_id>", methods=["PUT"])
def update_medication(med_id):
    body = request.get_json(force=True)
    name = body.get("name")
    time_str = body.get("time")

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            "UPDATE medications SET name=%s, time=%s WHERE id=%s",
            (name, time_str, med_id),
        )
        conn.commit()
        return jsonify({"updated": cur.rowcount > 0})
    finally:
        cur.close()
        conn.close()


@app.route("/medications/<med_id>", methods=["PATCH"])
def set_medication_done(med_id):
    """카메라 트래킹(TrackingScreen)에서 3초 이상 복용이 확인되면 호출되는 엔드포인트."""
    body = request.get_json(force=True)
    is_done = bool(body.get("is_done"))
    taken_at = datetime.now() if is_done else None

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            "UPDATE medications SET is_done=%s, taken_at=%s WHERE id=%s",
            (int(is_done), taken_at, med_id),
        )
        conn.commit()
        return jsonify({"updated": cur.rowcount > 0})
    finally:
        cur.close()
        conn.close()


@app.route("/medications/<med_id>", methods=["DELETE"])
def delete_medication(med_id):
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("DELETE FROM medications WHERE id=%s", (med_id,))
        conn.commit()
        return jsonify({"deleted": cur.rowcount > 0})
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
