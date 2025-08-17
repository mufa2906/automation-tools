FROM python:3.11-slim

# Set working directory di container
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy semua file project
COPY . .

# Expose port untuk API
EXPOSE 8000

# Jalankan server
#DEVELOPMENT
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
#PRODUCTION
#CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
