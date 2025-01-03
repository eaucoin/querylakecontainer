# Stage 1: Base Image with Dependencies
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04 AS base

# Set work directory
WORKDIR /app

# Install OS-level dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    build-essential \
    tesseract-ocr \
    libtesseract-dev \
    python3.10 \
    python3-pip \
    python3.10-venv \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Set up Python environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install exllamav2 from source
WORKDIR /exllamav2
RUN git clone https://github.com/turboderp/exllamav2
WORKDIR /exllamav2
RUN pip install -r requirements.txt
RUN pip install .

# Copy backend files
COPY ./backend/QueryLake /app/backend/QueryLake
COPY ./backend/requirements.txt /app/backend/requirements.txt
COPY ./backend/setup.py /app/backend/setup.py
COPY ./init.sql /docker-entrypoint-initdb.d/init.sql
COPY ./backend/restart_database.sh /app/backend/

# Install Python dependencies
WORKDIR /app/backend
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Set up Node.js environment
ARG NODE_VERSION=20
ENV NVM_DIR=/usr/local/nvm
ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH
RUN mkdir -p $NVM_DIR
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm use v$NODE_VERSION \
    && nvm alias default v$NODE_VERSION

# Copy frontend files
COPY ./frontend /app/frontend

# Install frontend dependencies
WORKDIR /app/frontend
RUN npm install

# Stage 2: Model Downloader
FROM base AS model-downloader
WORKDIR /app

# Copy necessary files for model download
COPY --from=base /app/setup.py /app/setup.py
COPY --from=base /app/QueryLake/other/default_config.json /app/QueryLake/other/default_config.json
COPY --from=base /app/QueryLake/typing /app/QueryLake/typing
COPY --from=base /app/QueryLake/misc_functions /app/QueryLake/misc_functions
COPY --from=base /app/QueryLake/operation_classes /app/QueryLake/operation_classes

# Run setup.py to download models - will pull from config.json
RUN python setup.py

# Stage 3: Backend
FROM base AS backend
WORKDIR /app

# Copy backend code
COPY --from=base /app/QueryLake /app/QueryLake
COPY --from=base /app/server.py /app/server.py
COPY --from=base /app/restart_database.sh /app/restart_database.sh
COPY --from=base /docker-entrypoint-initdb.d/init.sql /docker-entrypoint-initdb.d/init.sql

# Copy downloaded models
COPY --from=model-downloader /app/models /app/models

# Copy generated config.json
COPY --from=model-downloader /app/config.json /app/config.json

# Expose the port for Ray Serve (and potentially others)
EXPOSE 8000 8265

# Stage 4: Frontend
FROM base AS frontend
WORKDIR /app/frontend

# Copy the built frontend from the previous stage
COPY --from=base /app/frontend/.next /app/frontend/.next
COPY --from=base /app/frontend/public /app/frontend/public
COPY --from=base /app/frontend/package*.json /app/frontend/
COPY --from=base /app/frontend/next.config.mjs /app/frontend/next.config.mjs
COPY --from=base /app/frontend/next-env.d.ts /app/frontend/next-env.d.ts
COPY --from=base /app/frontend/tsconfig.json /app/frontend/tsconfig.json
COPY --from=base /app/frontend/server.js /app/frontend/server.js

# Expose the port for Next.js
EXPOSE 3001

# Stage 5: Final Image
FROM base
WORKDIR /app

# Copy backend and frontend from previous stages
COPY --from=backend /app /app
COPY --from=frontend /app/frontend /app/frontend

# Copy the startup script
COPY ./startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Set environment variables
ENV POSTGRES_USER=querylake_access
ENV POSTGRES_PASSWORD=querylake_access_password
ENV POSTGRES_DB=querylake_database
ENV NEXT_PUBLIC_APP_URL=http://localhost:8001
ENV OAUTH_SECRET_KEY=<YOUR_SECRET_KEY> # Generate a strong secret key
ENV CONFIG_FILE=/app/config.json

# Start the application
CMD ["/app/startup.sh"]