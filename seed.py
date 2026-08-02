import sqlite3
from datetime import datetime, timedelta

# الاتصال بقاعدة البيانات المحلية للعيادة
conn = sqlite3.connect('dental.db')
cursor = conn.cursor()

# حساب تواريخ الاشتراكات حية بناءً على تاريخ اليوم (2026)
today = datetime.utcnow()
active_expiry = today + timedelta(days=30)   # اشتراك ساري لمدة شهر
expired_expiry = today - timedelta(days=1)   # اشتراك منتهي منذ الأمس

# ضخ البيانات التجريبية داخل جدول الحسابات
cursor.execute("""
INSERT OR IGNORE INTO users (doctor_name, email, hashed_password, subscription_expires_at, is_active)
VALUES 
('د. فارس حلاوي', 'active@dental.com', 'faras2026', ?, 1),
('د. عيادة منتهية', 'expired@dental.com', '123456', ?, 1)
""", (active_expiry.strftime('%Y-%m-%d %H:%M:%S'), expired_expiry.strftime('%Y-%m-%d %H:%M:%S')))

conn.commit()
conn.close()
print("🚀 تم ضخ الحساب النشط والحساب المحظور بنجاح داخل قاعدة البيانات!")
