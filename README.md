# 🚀 Serverless Batch Processing Pipeline (S3 → Lambda → AWS Batch)

This project implements a **reusable, cloud-native pipeline** for automated batch processing using an event-driven architecture. It is designed so that **the only thing you need to change is the Docker image and the processing script** — the infrastructure, orchestration, and deployment are fully generic.

The reference implementation processes images (horizontal flip), but the same pipeline can be used for any heavy workload: AI inference, video transcoding, data transformation, document parsing, etc.

---

## 🎯 How it works

1. A file is uploaded to `s3://[bucket]/input/`
2. S3 fires an `ObjectCreated` event that triggers a Lambda function
3. Lambda submits a job to AWS Batch, passing the bucket name and file key as environment variables
4. AWS Batch spins up a Fargate container that runs your processing code
5. The container reads the input from S3, processes it, and writes the result to `s3://[bucket]/output/`
6. Once finished, Fargate automatically de-provisions — you pay only for what you use

---

## 🏗️ Infrastructure

| Component | Role |
| :--- | :--- |
| **Amazon S3** | Input (`input/`) and output (`output/`) storage |
| **AWS Lambda** | Event bridge between S3 and Batch |
| **AWS Batch (Fargate)** | On-demand container execution, no servers to manage |
| **Amazon ECR** | Private Docker registry for your processing image |
| **IAM** | Least-privilege roles for Lambda, Batch, and ECS |

---

## 🔁 Adapting this pipeline to your use case

The pipeline is fully generic. To use it for a different workload:

**1. Replace `processor.py`** with your own logic. The only contract is:
```python
import os
BUCKET = os.environ["BUCKET"]      # bucket name, injected by Lambda
INPUT_KEY = os.environ["INPUT_KEY"] # path of the uploaded file, e.g. input/file.jpg
```
Read from `s3://BUCKET/INPUT_KEY`, process, write to `s3://BUCKET/output/`.

**2. Update the `Dockerfile`** to install your dependencies:
```dockerfile
FROM python:3.12-slim
RUN pip install --no-cache-dir your-library boto3
COPY processor.py .
CMD ["python", "processor.py"]
```

That's it. Run `./deploy.sh` and the pipeline is live.

---

## 🚀 Deployment

### Prerequisites
- AWS CLI configured with admin credentials
- Docker installed locally

### Steps
```bash
chmod +x deploy.sh
./deploy.sh
```

The script creates all resources from scratch and is **idempotent** — safe to run multiple times. Resources that already exist are reused, not recreated.

### Test it
```bash
aws s3 cp test.jpg s3://[bucket-name]/input/test.jpg
```

### Monitor
- **Lambda logs:** CloudWatch → Log groups → `/aws/lambda/[lambda-name]`
- **Batch job status:** AWS Console → Batch → Jobs
- **Container logs:** CloudWatch → Log groups → `/aws/batch/job`
- **Result:** `aws s3 ls s3://[bucket-name]/output/`

---

## 🧹 Cleanup

```bash
chmod +x clean.sh
./clean.sh
```
