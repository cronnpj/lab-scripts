FROM python:3.11-slim

WORKDIR /app

# Install dependencies (Flask now, we can add more later)
RUN pip install --no-cache-dir flask

# Copy app code
COPY . /app

EXPOSE 5000

CMD ["python", "app.py"]
