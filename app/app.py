import os
import time
import datetime
from flask import Flask, render_template_string

app = Flask(__name__)

# Configuración de base de datos desde variables de entorno
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")

def get_db_connection():
    """Establece conexión a PostgreSQL con reintentos para soportar el arranque lento del servicio DB."""
    import psycopg2
    retries = 10
    conn = None
    while retries > 0:
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
                port=DB_PORT
            )
            return conn
        except psycopg2.OperationalError as e:
            print(f"Error de conexión a la base de datos: {e}. Reintentando en 2 segundos... ({retries} reintentos restantes)")
            retries -= 1
            time.sleep(2)
    raise Exception("No se pudo conectar a la base de datos después de varios intentos.")

def init_db():
    """Crea la tabla visitas si no existe."""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS visitas (
            id SERIAL PRIMARY KEY,
            fecha_hora TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
    """)
    conn.commit()
    cur.close()
    conn.close()

# Inicializar la base de datos al arrancar la aplicación
try:
    init_db()
except Exception as e:
    print(f"Error de inicialización de BD: {e}")

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VZeta - Sistema de Registro de Visitas</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: rgba(30, 41, 59, 0.7);
            --border-color: rgba(255, 255, 255, 0.1);
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --accent-color: #38bdf8;
            --accent-glow: rgba(56, 189, 248, 0.4);
            --success-color: #34d399;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Outfit', sans-serif;
            background-color: var(--bg-color);
            background-image: 
                radial-gradient(at 0% 0%, rgba(56, 189, 248, 0.15) 0px, transparent 50%),
                radial-gradient(at 100% 100%, rgba(139, 92, 246, 0.15) 0px, transparent 50%);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            padding: 2rem 1rem;
            overflow-x: hidden;
        }

        .container {
            width: 100%;
            max-width: 600px;
            perspective: 1000px;
        }

        .card {
            background: var(--card-bg);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid var(--border-color);
            border-radius: 24px;
            padding: 3rem 2rem;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
            text-align: center;
            transition: transform 0.5s ease, box-shadow 0.5s ease;
            position: relative;
            overflow: hidden;
        }

        .card::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 200%;
            height: 100%;
            background: linear-gradient(
                90deg, 
                transparent, 
                rgba(255, 255, 255, 0.05), 
                transparent
            );
            transition: 0.5s;
            pointer-events: none;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 30px 60px rgba(0, 0, 0, 0.4), 0 0 30px rgba(56, 189, 248, 0.1);
        }

        .card:hover::before {
            left: 100%;
            transition: 0.8s ease-in-out;
        }

        .logo {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(135deg, #38bdf8 0%, #818cf8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
            letter-spacing: -1px;
        }

        .tagline {
            font-size: 0.95rem;
            color: var(--text-secondary);
            margin-bottom: 2.5rem;
            text-transform: uppercase;
            letter-spacing: 2px;
            font-weight: 600;
        }

        .counter-wrapper {
            position: relative;
            display: inline-block;
            margin-bottom: 2.5rem;
        }

        .counter-glow {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 140px;
            height: 140px;
            background: var(--accent-glow);
            border-radius: 50%;
            filter: blur(30px);
            z-index: 1;
            opacity: 0.6;
            animation: pulse 3s infinite ease-in-out;
        }

        .counter-circle {
            position: relative;
            z-index: 2;
            width: 160px;
            height: 160px;
            border-radius: 50%;
            background: rgba(15, 23, 42, 0.8);
            border: 2px solid var(--accent-color);
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            box-shadow: inset 0 0 20px rgba(56, 189, 248, 0.2);
        }

        .counter-value {
            font-size: 3.5rem;
            font-weight: 800;
            color: var(--text-primary);
            line-height: 1;
        }

        .counter-label {
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            color: var(--accent-color);
            margin-top: 5px;
            font-weight: 600;
        }

        .status {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            font-size: 0.9rem;
            color: var(--text-secondary);
            margin-bottom: 2.5rem;
            background: rgba(15, 23, 42, 0.4);
            padding: 8px 16px;
            border-radius: 30px;
            border: 1px solid var(--border-color);
            display: inline-flex;
        }

        .status-dot {
            width: 8px;
            height: 8px;
            background-color: var(--success-color);
            border-radius: 50%;
            box-shadow: 0 0 8px var(--success-color);
            animation: blink 2s infinite ease-in-out;
        }

        .recent-title {
            text-align: left;
            font-size: 1rem;
            font-weight: 600;
            color: var(--text-primary);
            margin-bottom: 1rem;
            padding-left: 5px;
            border-left: 3px solid var(--accent-color);
            line-height: 1;
        }

        .visits-list {
            list-style: none;
            width: 100%;
            background: rgba(15, 23, 42, 0.3);
            border-radius: 12px;
            overflow: hidden;
            border: 1px solid var(--border-color);
            margin-bottom: 2rem;
        }

        .visit-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
            font-size: 0.85rem;
            color: var(--text-secondary);
            transition: background 0.3s;
        }

        .visit-item:last-child {
            border-bottom: none;
        }

        .visit-item:hover {
            background: rgba(255, 255, 255, 0.02);
            color: var(--text-primary);
        }

        .visit-index {
            color: var(--accent-color);
            font-weight: 600;
        }

        .footer {
            margin-top: 2rem;
            font-size: 0.8rem;
            color: var(--text-secondary);
            text-align: center;
        }

        .footer p {
            margin-bottom: 5px;
        }

        .footer-name {
            color: var(--text-primary);
            font-weight: 600;
        }

        @keyframes pulse {
            0%, 100% {
                transform: translate(-50%, -50%) scale(1);
                opacity: 0.5;
            }
            50% {
                transform: translate(-50%, -50%) scale(1.1);
                opacity: 0.8;
            }
        }

        @keyframes blink {
            0%, 100% { opacity: 0.4; }
            50% { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="logo">VZeta Systems</div>
            <div class="tagline">Control de Infraestructura</div>
            
            <div class="counter-wrapper">
                <div class="counter-glow"></div>
                <div class="counter-circle">
                    <div class="counter-value">{{ total_visitas }}</div>
                    <div class="counter-label">Visitas</div>
                </div>
            </div>

            <div>
                <div class="status">
                    <span class="status-dot"></span>
                    <span>Conectado a PostgreSQL</span>
                </div>
            </div>

            {% if ultimas_visitas %}
            <div class="recent-title">Últimos Registros (Servidor local)</div>
            <ul class="visits-list">
                {% for visita in ultimas_visitas %}
                <li class="visit-item">
                    <span class="visit-index">#{{ visita[0] }}</span>
                    <span>{{ visita[1].strftime('%d/%m/%Y %H:%M:%S') }}</span>
                </li>
                {% endfor %}
            </ul>
            {% endif %}

            <div class="footer">
                <p>EFT Infraestructura de Aplicaciones I</p>
                <p>Desplegado por: <span class="footer-name">Hugo Cuellar</span></p>
            </div>
        </div>
    </div>
</body>
</html>
"""

@app.route("/")
def index():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Registrar la visita actual
        cur.execute("INSERT INTO visitas DEFAULT VALUES;")
        conn.commit()
        
        # Obtener el total de visitas
        cur.execute("SELECT COUNT(*) FROM visitas;")
        total_visitas = cur.fetchone()[0]
        
        # Obtener las últimas 5 visitas
        cur.execute("SELECT id, fecha_hora FROM visitas ORDER BY id DESC LIMIT 5;")
        ultimas_visitas = cur.fetchall()
        
        cur.close()
        conn.close()
        
        return render_template_string(
            HTML_TEMPLATE, 
            total_visitas=total_visitas, 
            ultimas_visitas=ultimas_visitas
        )
    except Exception as e:
        return f"Error en la aplicación: {e}", 500

if __name__ == "__main__":
    # La aplicación corre en el puerto 5000 expuesto
    app.run(host="0.0.0.0", port=5000)
