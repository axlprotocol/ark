FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY arknet.py .
COPY node_id* ./
CMD ["python", "arknet.py"]
EXPOSE 8910
