FROM python:latest

COPY ./src/. .
RUN python3 -m pip install -r requirements.txt

ENTRYPOINT ["python3", "main.py", "--bind=0.0.0.0:8443", "--certfile=/ssl/tls.crt", "--keyfile=/ssl/tls.key"]
