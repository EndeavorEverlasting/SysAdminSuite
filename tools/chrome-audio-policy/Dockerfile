FROM python:3.12-alpine
WORKDIR /app
COPY tools/chrome-audio-policy/policy.py /app/policy.py
USER 65534:65534
ENTRYPOINT ["python3", "/app/policy.py"]
