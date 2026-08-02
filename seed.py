import sqlite3
import secrets
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "dental.db"


def generate_hex_token() -> str:
    return secrets.token_hex(3).upper()


monthly_keys = []
annual_keys = []

for _ in range(5):
    monthly_keys.append(f"FARAS-M-{generate_hex_token()}")

for _ in range(5):
    annual_keys.append(f"FARAS-Y-{generate_hex_token()}")

with sqlite3.connect(DB_PATH) as conn:
    cursor = conn.cursor()

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS activation_keys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key_code TEXT UNIQUE,
            duration_days INTEGER NOT NULL,
            is_used INTEGER NOT NULL DEFAULT 0,
            used_by_email TEXT
        )
        """
    )

    for key_code in monthly_keys:
        cursor.execute(
            """
            INSERT OR IGNORE INTO activation_keys (key_code, duration_days, is_used, used_by_email)
            VALUES (?, 30, 0, NULL)
            """,
            (key_code,),
        )

    for key_code in annual_keys:
        cursor.execute(
            """
            INSERT OR IGNORE INTO activation_keys (key_code, duration_days, is_used, used_by_email)
            VALUES (?, 365, 0, NULL)
            """,
            (key_code,),
        )

    conn.commit()

print("\n💳 تم إنشاء دفعة جديدة من أكواد التفعيل بنجاح!\n")
print("📅 الأكواد الشهرية (30 يوم):")
for key in monthly_keys:
    print(f"   • {key}")

print("\n📆 الأكواد السنوية (365 يوم):")
for key in annual_keys:
    print(f"   • {key}")

print("\n✅ تم حفظ جميع الأكواد في قاعدة البيانات المحلية dental.db")
