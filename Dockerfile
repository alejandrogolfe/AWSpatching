# Imagen base oficial de AWS Lambda para Python
FROM public.ecr.aws/lambda/python:3.12

# Copiar requirements e instalar dependencias
COPY requirements.txt ${LAMBDA_TASK_ROOT}
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código
COPY lambda_function.py ${LAMBDA_TASK_ROOT}

# Handler
CMD ["lambda_function.lambda_handler"]