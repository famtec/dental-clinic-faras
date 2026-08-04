import os

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

# مسار قاعدة البيانات المحلي أو من المتغير البيئي DATABASE_URL
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dental.db")

engine_kwargs = {}
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    engine_kwargs["connect_args"] = {"check_same_thread": False}

engine = create_engine(SQLALCHEMY_DATABASE_URL, **engine_kwargs)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def init_db():
    Base.metadata.create_all(bind=engine)

    if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
        inspector = inspect(engine)
        if "patients" in inspector.get_table_names():
            columns = {column["name"] for column in inspector.get_columns("patients")}
            if "doctor_name" not in columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE patients ADD COLUMN doctor_name VARCHAR"))
            if "chart_state" not in columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE patients ADD COLUMN chart_state TEXT"))

        if "users" in inspector.get_table_names():
            user_columns = {column["name"] for column in inspector.get_columns("users")}
            if "tier" not in user_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE users ADD COLUMN tier VARCHAR NOT NULL DEFAULT 'standard'"))

        if "financial_transactions" in inspector.get_table_names():
            finance_columns = {column["name"] for column in inspector.get_columns("financial_transactions")}
            if "patient_id" not in finance_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE financial_transactions ADD COLUMN patient_id INTEGER"))

        if "appointments" in inspector.get_table_names():
            appointment_columns = {column["name"] for column in inspector.get_columns("appointments")}
            if "patient_name" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN patient_name VARCHAR NOT NULL DEFAULT ''"))
            if "appointment_time" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN appointment_time VARCHAR NOT NULL DEFAULT ''"))
            if "procedure_type" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN procedure_type VARCHAR NOT NULL DEFAULT ''"))
            if "status" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN status VARCHAR NOT NULL DEFAULT 'Pending'"))
            if "appointment_date" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN appointment_date DATETIME"))
            if "notes" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN notes VARCHAR"))


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()