# 🚀 Serverless Image Processing Pipeline (AWS Batch & Event-Driven AI)

This project implements a **Cloud-Native architecture** designed for automated, large-scale image processing. It leverages an **Event-Driven** approach to optimize operational costs, ensuring that high-performance computing resources are provisioned only when data is available for processing.

---

## 🎯 Project Objective

The system automates the workflow from the moment an image is captured until it is processed by an AI model or a computer vision script.

* **Trigger:** An image upload to an **Amazon S3** bucket.
* **Orchestration:** An **AWS Lambda** function detects the event and submits a job to **AWS Batch**.
* **Processing:** A Docker container running on **AWS Fargate** executes the heavy-duty computational task, providing full isolation and scalability without the need to manage underlying servers.

---

## 🏗️ Technical Architecture



The deployment is fully automated via a Bash orchestration script that configures the following infrastructure:

| Component | Function |
| :--- | :--- |
| **Amazon S3** | Distributed storage for input (`input/`) and output (`output/`) images. |
| **AWS Lambda** | Serverless microservice acting as an event bridge between S3 and AWS Batch. |
| **AWS Batch (Fargate)** | Computational job manager that provisions containers on-demand. |
| **Amazon ECR** | Private Docker registry hosting the core processing logic. |
| **IAM & Security** | Fine-grained "Least Privilege" policy configuration to ensure infrastructure security. |

---

## 🛠️ Execution Flow

1.  **Ingestion:** A file is uploaded to `s3://[bucket-name]/input/`.
2.  **Notification:** S3 triggers an `ObjectCreated` event, invoking the Lambda function.
3.  **Scheduling:** Lambda submits the job to the **AWS Batch** queue, passing the file metadata as environment variables.
4.  **Computation:** AWS Batch instantiates a container based on the **ECR** image, processes the image, and writes the results to the output directory.
5.  **Efficiency:** Upon task completion, computational resources are automatically de-provisioned.

---

## 🚀 Deployment Guide

### Prerequisites
* AWS CLI configured with appropriate administrative credentials.
* Docker installed locally for image building.
* A `Dockerfile` containing the processing logic in the root directory.

### Installation Steps
1.  Clone this repository.
2.  Grant execution permissions to the script:
    ```bash
    chmod +x deploy.sh
    ```
3.  Execute the automated deployment:
    ```bash
    ./deploy.sh
    ```

The script will provide a summary of the created resources and save the environment variables to a local `.deployment-config` file for management.

---

## 🧠 Strategic Value for AI Workloads

* **Horizontal Scalability:** Capable of processing thousands of images concurrently without performance bottlenecks.
* **Portability:** Docker encapsulation ensures that the execution environment (including dependencies like OpenCV, PyTorch, or TensorFlow) remains identical from development to production.
* **Cost Optimization:** By utilizing Fargate, there are zero idle-time costs; billing is strictly based on the exact duration of the processing task.

---

## 🧹 Resource Cleanup

To decommission the infrastructure and avoid unnecessary AWS charges:
```bash
chmod +x clean.sh
./clean.sh