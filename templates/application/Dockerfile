FROM python:3.12-slim

WORKDIR /app

COPY src/app.py .

ENV PORT=8080 \
    APP_NAME=myapp

EXPOSE 8080

USER 65532

CMD ["python", "app.py"]
