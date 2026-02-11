FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir pillow boto3

COPY processor.py .

CMD ["python", "processor.py"]
