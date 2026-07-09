# Imagen base recomendada por el caso (fijada a 3.12-slim para evitar problemas de compatibilidad con Python 3.14 y psycopg2)
FROM python:3.12-slim

# Metadatos LABEL de la imagen para el cumplimiento de estándares
LABEL maintainer="Hugo Cuellar"
LABEL version="1.0.0"
LABEL description="Aplicación Web Flask de registro de visitas para VZeta"

# Establecer variables de entorno de Python
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Directorio de trabajo del contenedor
WORKDIR /app

# Copiar el archivo de requisitos e instalar las dependencias
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el código fuente de la aplicación Flask
COPY app.py /app/

# Exponer el puerto por defecto de Flask
EXPOSE 5000

# Comando para ejecutar la aplicación
CMD ["python", "app.py"]
