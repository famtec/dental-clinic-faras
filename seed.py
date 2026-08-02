import sqlite3

# 1. الاتصال بقاعدة البيانات
conn = sqlite3.connect('dental.db')
cursor = conn.cursor()

# 2. توليد كود التفعيل الفخم الخاص بك (30 يوماً)
my_activation_code = "FARAS-30DAYS-2026"

cursor.execute("""
INSERT OR IGNORE INTO activation_keys (key_code, duration_days, is_used, used_by_email)
VALUES (?, 30, 0, NULL)
""", (my_activation_code,))

conn.commit()
conn.close()

print(f"💳 تم توليد بطاقة تفعيل العيادات الذكية بنجاح!")
print(f"🔑 كود التفعيل المتاح للبيع: {my_activation_code}")
