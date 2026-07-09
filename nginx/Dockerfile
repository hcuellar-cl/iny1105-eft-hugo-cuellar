# Imagen base liviana oficial de NGINX
FROM nginx:alpine

# Metadatos LABEL de la imagen para el cumplimiento de estándares
LABEL maintainer="Hugo Cuellar"
LABEL version="1.0.0"
LABEL description="Reverse Proxy NGINX para el stack de VZeta"

# Instalar openssl y generar certificado SSL auto-firmado para soporte HTTPS
RUN apk add --no-cache openssl && \
    mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=CL/ST=RM/L=Santiago/O=VZeta/CN=localhost"

# Copiar la configuración personalizada del Reverse Proxy al contenedor
COPY default.conf /etc/nginx/conf.d/default.conf

# Exponer los puertos HTTP y HTTPS
EXPOSE 80 443
